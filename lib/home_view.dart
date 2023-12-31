import 'dart:developer';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:docx_template/docx_template.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html/parser.dart' as parserLibrary;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:docx_template/docx_template.dart' as docx;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';

class Chapter {
  String title;
  String text;

  Chapter(this.title, this.text);

  Map<String, dynamic> toJson() {
    return {'title': title, 'text': text};
  }
}

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  @override
  void initState() {
    _getStoragePermission();
    super.initState();
  }

  int chapters = 0;
  int lessons = 0;
  Future<void> _getStoragePermission() async {
    DeviceInfoPlugin plugin = DeviceInfoPlugin();
    AndroidDeviceInfo android = await plugin.androidInfo;
    if (android.version.sdkInt < 33) {
      if (await Permission.storage.request().isGranted) {
        setState(() {
          permissionGranted = true;
        });
      } else if (await Permission.storage.request().isPermanentlyDenied) {
        await openAppSettings();
      } else if (await Permission.audio.request().isDenied) {
        setState(() {
          permissionGranted = false;
        });
      }
    } else {
      if (await Permission.photos.request().isGranted) {
        setState(() {
          permissionGranted = true;
        });
      } else if (await Permission.photos.request().isPermanentlyDenied) {
        await openAppSettings();
      } else if (await Permission.photos.request().isDenied) {
        setState(() {
          permissionGranted = false;
        });
      }
    }
  }

  List<Chapter> result = [];
  bool isLoading = false;
  bool permissionGranted = false;
  int page = 1;

  var finishedCount = 0;
  late int allCount;
  Future<List<Chapter>> extractData(String url) async {
    if (url.endsWith('/') == false) url += '/';
    final lastPageNumber = await getLastPageNumber('${url}1');
    allCount = lastPageNumber;
    final urls = List<String>.empty(growable: true);
    for (var i = 1; i <= lastPageNumber; i++) {
      urls.add('$url$i');
      print(i);
    }
    final pagesFuturs = urls.map((e) async => await getPage(e));
    final pages = await Future.wait(pagesFuturs);
    print('');

    final newPages = pages.skip(1).fold(List<Chapter>.from([pages.first]),
        (previousValue, element) {
      if (previousValue.last.title != element.title) {
        chapters++;
        previousValue.add(Chapter(element.title, ''));
      }

      previousValue.last.text += '${element.text}\n';
      return previousValue;
    });
    return newPages;
  }

  Future<Chapter> getPage(String url) async {
    http.Response response;
    while (true) {
      try {
        response =
            await http.get(Uri.parse(url)).timeout(const Duration(minutes: 5));
        break;
      } catch (e) {
        continue;
      }
    }

    if (response.statusCode != 200) throw ArgumentError('url is wrong >> $url');

    final parser = parserLibrary.parse(response.body);
    final text = parser
        .querySelector('.nass.margin-top-10')
        ?.children
        .map((e) => '${e.text}\n')
        .reduce((value, element) => '$value $element');

    if (text == null) throw 'can not get the page';

    var level = parser
        .querySelector('.size-12')
        ?.children
        .where((c) => c.localName == 'a')
        .skip(1)
        .map((e) => e.text)
        .reduce((value, element) => '$value $element');
    if (level == null) throw 'can not find the chapter name';

    finishedCount++;
    stdout.write('\rfinish ($finishedCount/$allCount)');
    return Chapter(level, text);
  }

  Future<int> getLastPageNumber(String url) async {
    var response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) throw ArgumentError('The url is wrong');
    var parser = parserLibrary.parse(response.body);
    return int.parse(parser
            .getElementsByClassName('btn btn-3d btn-white btn-sm')
            .skip(4)
            .first
            .attributes['href']
            ?.split('/')
            .last
            .split('#')
            .first ??
        '-1');
  }

  Future<void> saveAsDocx(List<Chapter> result) async {
    try {
      final fileDirectory = await FilePicker.platform.getDirectoryPath();
      final data = await rootBundle.load('template.docx');
      final bytes = data.buffer.asUint8List();

      final docx = await DocxTemplate.fromBytes(bytes);
      // final selectedDirectory = await FilePicker.platform.getDirectoryPath();
      // final filePath = '$selectedDirectory/document.docx';
      final contentList = <Content>[];
      final b = result.iterator;
      for (var chapter in result) {
        b.moveNext();
        final c = PlainContent("value")
          // ..add(TextContent("docname", "Book generated"))
          ..add(TextContent("titles", chapter.title))
          ..add(TextContent("multilineText", chapter.text));
        contentList.add(c);
      }
      log(contentList.length.toString(), name: "data");
      Content c = Content();
      c
        ..add(TextContent("normalText", contentList))
        ..add(TextContent("bold", result.first.title))
        ..add(TextContent("multilineText", result.first.text))
        ..add(TextContent("docname", "Book regenerated"));

      // log(wholeContent);
      final docGenerated = await docx.generate(c);
      final fileGenerated = File('$fileDirectory/generated.docx');
      if (docGenerated != null) await fileGenerated.writeAsBytes(docGenerated);

      print("Docx file saved.");
    } catch (e) {
      print("Error: $e");
    }
  }

  Future<void> saveAsTxt(List<Chapter> result) async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath();
      final filePath = '$selectedDirectory/document.txt';
      final file = File(filePath);
      if (await file.exists() == true) {
        file.delete();
      }
      await file.create(recursive: true);
      final text = result
          .map((chapter) => '${chapter.title}\n${chapter.text}\n')
          .join('\n');
      await file.writeAsString(text).then((value) {
        print("TXT file saved to Downloads folder.");
      });
    } catch (e) {
      print("Error: $e");
    }
  }

  Future<void> saveAsPdf(List<Chapter> result) async {
    int i = 0;
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      final filePath = '$selectedDirectory/document.pdf';
      final file = File(filePath);
      if (await file.exists() == true) {
        file.delete();
      }
      await file.create(recursive: true);
      final pdf = pw.Document();
      var titleStyle = await PdfGoogleFonts.amiriBold();
      var textStyle = await PdfGoogleFonts.notoNaskhArabicRegular();
      // print(result.length);
      // log(chapters.toString());

      for (var chapter in result) {
        // i++;
        // print(i);
        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      chapter.title,
                      style: pw.TextStyle(font: titleStyle),
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.Text(
                      chapter.text,
                      style: pw.TextStyle(font: titleStyle),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }

      await file.writeAsBytes(await pdf.save());
      print("PDF file saved to Downloads folder.");
    } catch (e) {
      print("Error: $e");
    }
  }

  String url = "";
  bool done = false;
  TextEditingController urlController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Al-Hossam'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextFormField(
                  decoration: const InputDecoration(labelText: 'Enter URL'),
                  controller: urlController,
                  onChanged: (value) {
                    setState(() {
                      print("بدأ جلب الكتاب");
                      url = value;
                      print(value);
                    });
                  },
                ),
              ),
              const SizedBox(height: 20.0),
              if (result.isNotEmpty)
                Column(
                  children: [
                    Text(
                      "تم جلب محتوى الكتاب بنجاح، الحمد لله",
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        color: isLoading ? Colors.blue : Colors.black,
                      ),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              const SizedBox(height: 20.0),
              ElevatedButton(
                onPressed:
                    isLoading ? null : () => fetchData(urlController.text),
                style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.all(Colors.blue),
                ),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      )
                    : const Text(
                        "بدأ",
                        style: TextStyle(fontSize: 16.0, color: Colors.white),
                      ),
              ),
              const SizedBox(height: 20.0),
              ElevatedButton(
                onPressed: isLoading
                    ? () => print("data not loaded")
                    : () {
                        print("making");
                        saveAsTxt(result);
                      },
                style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.all(Colors.green),
                ),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      )
                    : const Text(
                        "حفظ كمستند TXT",
                        style: TextStyle(fontSize: 16.0, color: Colors.white),
                      ),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? () => print("data not loaded")
                    : () {
                        print("making");
                        saveAsDocx(result);
                      },
                style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.all(Colors.green),
                ),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      )
                    : const Text(
                        "حفظ كمستند Word",
                        style: TextStyle(fontSize: 16.0, color: Colors.white),
                      ),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () {
                        print("making pdf");
                        saveAsPdf(result);
                      },
                style: ButtonStyle(
                  backgroundColor: MaterialStateProperty.all(Colors.red),
                ),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      )
                    : const Text(
                        "حفظ كمستند PDF",
                        style: TextStyle(fontSize: 16.0, color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> fetchData(String desiredUrl) async {
    setState(() {
      isLoading = true;
      result = [];
    });

    try {
      final chapters = await extractData(desiredUrl);
      setState(() {
        result = chapters;
        isLoading = false;
        done = true;
      });
    } catch (e) {
      setState(() {
        result = [
          Chapter("Error", "An error occurred: $e")
        ]; // Create an error chapter
        isLoading = false;
      });
    }
  }
}
