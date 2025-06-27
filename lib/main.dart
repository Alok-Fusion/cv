import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Resume Builder',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: ResumeHomePage(),
    );
  }
}

class ResumeHomePage extends StatefulWidget {
  @override
  _ResumeHomePageState createState() => _ResumeHomePageState();
}

class _ResumeHomePageState extends State<ResumeHomePage> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _spokenText = '';
  String _status = 'Press the mic and start speaking';
  Timer? _silenceTimer;

  void _listenToggle() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          print('Speech status: $val');
          if (val == 'done' && _isListening) {
            // Auto-restart listening when it stops automatically
            _speech.listen(
              onResult: (val) {
                setState(() {
                  _spokenText = val.recognizedWords;
                  _resetSilenceTimer(); // Reset timer on new speech input
                });
              },
              listenMode: stt.ListenMode.dictation,
              partialResults: true,
            );
          } else if (val == 'notListening') {
            setState(() => _isListening = false);
            _silenceTimer?.cancel(); // Cancel timer if not listening
          }
        },
        onError: (val) {
          setState(() {
            _status = 'Error: ${val.errorMsg}';
            _isListening = false;
            _silenceTimer?.cancel(); // Cancel timer on error
          });
        },
      );
      if (available) {
        setState(() {
          _isListening = true;
          _status = 'Listening...';
          _spokenText = '';
        });
        _resetSilenceTimer(); // Start the silence timer
        _speech.listen(
          onResult: (val) {
            setState(() {
              _spokenText = val.recognizedWords;
              _resetSilenceTimer(); // Reset timer on new speech input
            });
          },
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
        );
      } else {
        setState(() {
          _status = 'Speech recognition not available';
        });
      }
    } else {
      await _speech.stop();
      setState(() {
        _isListening = false;
        _status = 'Stopped listening';
        _silenceTimer?.cancel(); // Cancel timer when stopping
      });
    }
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel(); // Cancel any existing timer
    _silenceTimer = Timer(Duration(seconds: 10), () {
      _speech.stop(); // Stop listening after 10 seconds of silence
      setState(() {
        _isListening = false;
        _status = 'Stopped listening due to silence';
      });
    });
  }

  Map<String, String> _parseResumeData(String text) {
    final nameRegex = RegExp(r'name is ([\w\s]+)', caseSensitive: false);
    final emailRegex = RegExp(r'email is ([\w@.\-]+)', caseSensitive: false);
    final phoneRegex =
        RegExp(r'phone number is ([\d\s\-+]+)', caseSensitive: false);
    final skillsRegex =
        RegExp(r'skills? (are|include) ([\w\s,]+)', caseSensitive: false);
    final educationRegex =
        RegExp(r'education (is|includes) ([\w\s,]+)', caseSensitive: false);
    final experienceRegex =
        RegExp(r'experience (is|includes) ([\w\s,]+)', caseSensitive: false);

    String getMatch(RegExp regex) {
      final match = regex.firstMatch(text);
      return match != null && match.groupCount >= 2
          ? match.group(2)!.trim()
          : '';
    }

    return {
      'Name': getMatch(nameRegex),
      'Email': getMatch(emailRegex),
      'Phone': getMatch(phoneRegex),
      'Skills': getMatch(skillsRegex),
      'Education': getMatch(educationRegex),
      'Experience': getMatch(experienceRegex),
    };
  }

  Future<void> _generateAndSavePdf() async {
    if (_spokenText.isEmpty) {
      setState(() => _status = 'No speech input to generate resume');
      return;
    }

    setState(() => _status = 'Generating resume PDF...');

    final resumeData = _parseResumeData(_spokenText);

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(20),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Resume',
                    style: pw.TextStyle(
                        fontSize: 28, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 20),
                if (resumeData['Name']!.isNotEmpty)
                  pw.Text('Name: ${resumeData['Name']}',
                      style: pw.TextStyle(fontSize: 18)),
                if (resumeData['Email']!.isNotEmpty)
                  pw.Text('Email: ${resumeData['Email']}',
                      style: pw.TextStyle(fontSize: 18)),
                if (resumeData['Phone']!.isNotEmpty)
                  pw.Text('Phone: ${resumeData['Phone']}',
                      style: pw.TextStyle(fontSize: 18)),
                pw.SizedBox(height: 20),
                if (resumeData['Skills']!.isNotEmpty)
                  pw.Column(children: [
                    pw.Text('Skills',
                        style: pw.TextStyle(
                            fontSize: 22, fontWeight: pw.FontWeight.bold)),
                    pw.Text(resumeData['Skills']!,
                        style: pw.TextStyle(fontSize: 16)),
                    pw.SizedBox(height: 20),
                  ]),
                if (resumeData['Education']!.isNotEmpty)
                  pw.Column(children: [
                    pw.Text('Education',
                        style: pw.TextStyle(
                            fontSize: 22, fontWeight: pw.FontWeight.bold)),
                    pw.Text(resumeData['Education']!,
                        style: pw.TextStyle(fontSize: 16)),
                    pw.SizedBox(height: 20),
                  ]),
                if (resumeData['Experience']!.isNotEmpty)
                  pw.Column(children: [
                    pw.Text('Experience',
                        style: pw.TextStyle(
                            fontSize: 22, fontWeight: pw.FontWeight.bold)),
                    pw.Text(resumeData['Experience']!,
                        style: pw.TextStyle(fontSize: 16)),
                  ]),
              ]),
        ),
      ),
    );

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/GeneratedResume.pdf');
      await file.writeAsBytes(await pdf.save());
      setState(() => _status = '✅ Resume PDF saved at: ${file.path}');
    } catch (e) {
      setState(() => _status = 'Error saving PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Voice Resume Builder')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(_status, style: TextStyle(fontSize: 18)),
            SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
              label: Text(_isListening ? 'Stop Listening' : 'Start Speaking'),
              onPressed: _listenToggle,
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(Icons.picture_as_pdf),
              label: Text('Generate Resume PDF'),
              onPressed: _generateAndSavePdf,
            ),
            SizedBox(height: 30),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _spokenText,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
