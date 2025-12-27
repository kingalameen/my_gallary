import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(MyApp(prefs: prefs));
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;
  const MyApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Gallery',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: SplashScreen(prefs: prefs),
    );
  }
}

class SplashScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const SplashScreen({super.key, required this.prefs});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 600), _decideNext);
  }

  void _decideNext() {
    final hasPassword = widget.prefs.getString('gallery_pass') != null;
    if (hasPassword) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AuthScreen(prefs: widget.prefs)));
    } else {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(prefs: widget.prefs)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library,
                size: 84, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text('My Gallery',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('Fast • Secure • Beautiful',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const AuthScreen({super.key, required this.prefs});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _controller = TextEditingController();
  String _error = '';

  void _submit() {
    final stored = widget.prefs.getString('gallery_pass');
    if (_controller.text == stored) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(prefs: widget.prefs)));
    } else {
      setState(() {
        _error = 'Incorrect password';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unlock Gallery')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Enter 6-digit password',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            if (_error.isNotEmpty)
              Text(_error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _submit, child: const Text('Unlock')),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const HomeScreen({super.key, required this.prefs});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<String> images = [];
  List<String> hidden = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    images =
        List.generate(12, (i) => 'https://picsum.photos/seed/${i + 1}/800/800');
    hidden = widget.prefs.getStringList('hidden_items') ?? [];
  }

  Future<void> _pick(ImageSource source) async {
    // Improved permission handling across Android/iOS
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) return;
    } else {
      // Use platform-specific permission: photos for iOS, storage for Android
      final status = await (Platform.isIOS
          ? Permission.photos.request()
          : Permission.storage.request());
      if (!status.isGranted) return;
    }

    final XFile? file = await _picker.pickImage(
        source: source, maxWidth: 2000, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final saved = await _saveImage(bytes);
    if (!mounted) return;
    setState(() {
      images.insert(0, saved);
    });
  }

  Future<String> _saveImage(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/img_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  void _openImage(String url) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ImageViewer(url: url)));
  }

  void _openEditor(String url) async {
    final result = await Navigator.of(context).push<String?>(
        MaterialPageRoute(builder: (_) => ImageEditor(initialPath: url)));
    if (!mounted) return;
    if (result != null) {
      setState(() {
        images.insert(0, result);
      });
    }
  }

  void _toggleHide(String url) async {
    final set = widget.prefs.getStringList('hidden_items') ?? [];
    if (set.contains(url)) {
      set.remove(url);
    } else {
      set.add(url);
    }
    await widget.prefs.setStringList('hidden_items', set);
    setState(() {
      hidden = set;
    });
  }

  void _setPassword() async {
    final code = await showDialog<String>(
        context: context,
        builder: (_) => SetPasswordDialog(prefs: widget.prefs));
    if (!mounted) return;
    if (code != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password set')));
    }
  }

  void _openHiddenArea() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => EnterPasswordDialog(prefs: widget.prefs));
    if (!mounted) return;
    if (ok == true) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => HiddenScreen(hidden: hidden)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleImages = images.where((i) => !hidden.contains(i)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: [
          IconButton(onPressed: _setPassword, icon: const Icon(Icons.lock)),
          IconButton(
              onPressed: _openHiddenArea, icon: const Icon(Icons.folder)),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final crossAxis = constraints.maxWidth > 900
            ? 5
            : constraints.maxWidth > 600
                ? 4
                : constraints.maxWidth > 400
                    ? 3
                    : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxis,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: visibleImages.length,
          itemBuilder: (context, idx) {
            final url = visibleImages[idx];
            return GestureDetector(
              onTap: () => _openImage(url),
              onDoubleTap: () => _openEditor(url),
              onLongPress: () => _toggleHide(url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildImageWidget(url),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: GestureDetector(
                        onTap: () => _toggleHide(url),
                        child: Container(
                          decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6)),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(Icons.visibility_off,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPickOptions(context),
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }

  Widget _buildImageWidget(String url) {
    if (url.startsWith('http')) {
      return Image.network(url, fit: BoxFit.cover);
    }
    // local file
    return Image.file(File(url), fit: BoxFit.cover);
  }

  void _showPickOptions(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pick(ImageSource.gallery);
                }),
            ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pick(ImageSource.camera);
                }),
            ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
  }
}

class ImageViewer extends StatelessWidget {
  final String url;
  const ImageViewer({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    // iPhone-like framed viewer
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(backgroundColor: Colors.black, elevation: 0),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 860),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: Colors.black87, width: 12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 20)
            ],
          ),
          child: Stack(
            children: [
              // screen area
              Positioned.fill(
                left: 18,
                right: 18,
                top: 48,
                bottom: 24,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(color: Colors.black, child: _content()),
                ),
              ),
              // notch illusion
              Positioned(
                top: 8,
                left: (420 / 2) - 60,
                child: Container(
                  width: 120,
                  height: 28,
                  decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (url.startsWith('http')) {
      return InteractiveViewer(child: Image.network(url, fit: BoxFit.contain));
    }
    return InteractiveViewer(child: Image.file(File(url), fit: BoxFit.contain));
  }
}

class ImageEditor extends StatefulWidget {
  final String initialPath;
  const ImageEditor({super.key, required this.initialPath});

  @override
  State<ImageEditor> createState() => _ImageEditorState();
}

class _ImageEditorState extends State<ImageEditor> {
  late Uint8List _bytes;
  bool _loading = true;
  final List<Uint8List> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Uint8List bytes = Uint8List(0);
    if (widget.initialPath.startsWith('http')) {
      try {
        final uri = Uri.parse(widget.initialPath);
        final client = HttpClient();
        final request = await client.getUrl(uri);
        final response = await request.close();
        final buffer = await consolidateHttpClientResponseBytes(response);
        bytes = Uint8List.fromList(buffer);
      } catch (e) {
        bytes = Uint8List(0);
      }
    } else {
      try {
        final file = File(widget.initialPath);
        bytes = await file.readAsBytes();
      } catch (e) {
        bytes = Uint8List(0);
      }
    }
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _history.clear();
      _history.add(bytes);
      _loading = false;
    });
  }

  Future<void> _applyAndSave() async {
    if (!mounted) return;
    setState(() => _loading = true);
    // final image processing already applied to _bytes; just save
    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(_bytes);
    if (!mounted) return;
    setState(() => _loading = false);
    Navigator.of(context).pop(file.path);
  }

  void _pushHistory(Uint8List bytes) {
    _history.add(bytes);
    if (_history.length > 20) _history.removeAt(0);
  }

  void _undo() {
    if (_history.length <= 1) return;
    _history.removeLast();
    setState(() {
      _bytes = _history.last;
    });
  }

  Future<void> _applyTransform(
      Future<Uint8List> Function(Uint8List) transformer) async {
    setState(() => _loading = true);
    try {
      final out = await transformer(_bytes);
      _pushHistory(out);
      setState(() {
        _bytes = out;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<Uint8List> _transformRotate(Uint8List bytes, int angle) async {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    final res = img.copyRotate(image, angle: angle);
    return Uint8List.fromList(img.encodePng(res));
  }

  Future<Uint8List> _transformFlipHorizontal(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    final res = img.flipHorizontal(image);
    return Uint8List.fromList(img.encodePng(res));
  }

  Future<Uint8List> _transformFlipVertical(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    final res = img.flipVertical(image);
    return Uint8List.fromList(img.encodePng(res));
  }

  Future<Uint8List> _transformGrayscale(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    final res = img.grayscale(image);
    return Uint8List.fromList(img.encodePng(res));
  }

  Future<Uint8List> _transformInvert(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    final res = img.invert(image);
    return Uint8List.fromList(img.encodePng(res));
  }

  Future<Uint8List> _transformCropSquare(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    final w = image.width;
    final h = image.height;
    final size = w < h ? w : h;
    final x = ((w - size) / 2).round();
    final y = ((h - size) / 2).round();
    final res = img.copyCrop(image, x: x, y: y, width: size, height: size);
    return Uint8List.fromList(img.encodePng(res));
  }

  Widget _preview() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return InteractiveViewer(child: Image.memory(_bytes, fit: BoxFit.contain));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Photo'),
        actions: [
          IconButton(onPressed: _undo, icon: const Icon(Icons.undo)),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: Center(child: _preview())),
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                      onPressed: () =>
                          _applyTransform((b) => _transformRotate(b, 90)),
                      icon: const Icon(Icons.rotate_right)),
                  IconButton(
                      onPressed: () =>
                          _applyTransform(_transformFlipHorizontal),
                      icon: const Icon(Icons.flip)),
                  IconButton(
                      onPressed: () => _applyTransform(_transformFlipVertical),
                      icon: const Icon(Icons.flip_camera_android)),
                  IconButton(
                      onPressed: () => _applyTransform(_transformGrayscale),
                      icon: const Icon(Icons.filter_b_and_w)),
                  IconButton(
                      onPressed: () => _applyTransform(_transformInvert),
                      icon: const Icon(Icons.invert_colors)),
                  TextButton(
                      onPressed: () => _applyTransform(_transformCropSquare),
                      child: const Text('Crop □')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                      onPressed: _applyAndSave,
                      icon: const Icon(Icons.save),
                      label: const Text('Save')),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel')),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

class SetPasswordDialog extends StatefulWidget {
  final SharedPreferences prefs;
  const SetPasswordDialog({super.key, required this.prefs});

  @override
  State<SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<SetPasswordDialog> {
  final TextEditingController _a = TextEditingController();
  final TextEditingController _b = TextEditingController();
  String _err = '';

  void _save() async {
    final a = _a.text.trim();
    final b = _b.text.trim();
    if (a.length != 6 || b.length != 6 || a != b) {
      setState(() {
        _err = 'Passwords must match and be 6 digits';
      });
      return;
    }
    await widget.prefs.setString('gallery_pass', a);
    if (!mounted) return;
    Navigator.of(context).pop(a);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set 6-digit password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: _a,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password')),
          TextField(
              controller: _b,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm')),
          if (_err.isNotEmpty)
            Text(_err, style: const TextStyle(color: Colors.red)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class EnterPasswordDialog extends StatefulWidget {
  final SharedPreferences prefs;
  const EnterPasswordDialog({super.key, required this.prefs});

  @override
  State<EnterPasswordDialog> createState() => _EnterPasswordDialogState();
}

class _EnterPasswordDialogState extends State<EnterPasswordDialog> {
  final TextEditingController _c = TextEditingController();
  String _err = '';

  void _check() {
    final stored = widget.prefs.getString('gallery_pass');
    if (stored != null && _c.text == stored) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _err = 'Wrong password';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: _c,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(labelText: '6-digit code')),
          if (_err.isNotEmpty)
            Text(_err, style: const TextStyle(color: Colors.red)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _check, child: const Text('Open')),
      ],
    );
  }
}

class HiddenScreen extends StatelessWidget {
  final List<String> hidden;
  const HiddenScreen({super.key, required this.hidden});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hidden')),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: hidden.length,
        itemBuilder: (context, i) => ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: hidden[i].startsWith('http')
                ? Image.network(hidden[i], fit: BoxFit.cover)
                : Image.file(File(hidden[i]), fit: BoxFit.cover)),
      ),
    );
  }
}
