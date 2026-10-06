import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

const _videoExt = ['mp4', 'mov', 'avi', 'mkv'];
const _imageExt = ['jpg', 'jpeg', 'png', 'webp', 'bmp'];
const _maxBytes = 50 * 1024 * 1024;

const _mime = {
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'avi': 'video/x-msvideo',
  'mkv': 'video/x-matroska',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
};

class AddAdScreen extends StatefulWidget {
  const AddAdScreen({super.key});

  @override
  State<AddAdScreen> createState() => _AddAdScreenState();
}

class _AddAdScreenState extends State<AddAdScreen> {
  final _title = TextEditingController();
  String _age = 'adults'; // teens = 10-20, adults = 20-49, seniors = 50-80
  String _gender = 'male';
  PlatformFile? _file;
  bool _busy = false;

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [..._videoExt, ..._imageExt],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.size > _maxBytes) {
      if (mounted) toast(context, 'File is larger than 50 MB. Please compress it.');
      return;
    }
    setState(() => _file = f);
  }

  Future<void> _upload() async {
    if (_title.text.trim().isEmpty) {
      toast(context, 'Enter an advertisement title');
      return;
    }
    if (_file == null || _file!.bytes == null) {
      toast(context, 'Choose a video or image file');
      return;
    }
    setState(() => _busy = true);
    final uid = supabase.auth.currentUser!.id;
    final ext = (_file!.extension ?? 'mp4').toLowerCase();
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await supabase.storage.from('ads').uploadBinary(
            path,
            _file!.bytes!,
            fileOptions: FileOptions(
                contentType: _mime[ext] ?? 'application/octet-stream',
                upsert: false),
          );
      try {
        await supabase.from('ads').insert({
          'title': _title.text.trim(),
          'age_group': _age,
          'gender': _gender,
          'file_path': path,
          'file_type': _videoExt.contains(ext) ? 'video' : 'image',
        });
      } catch (e) {
        await supabase.storage.from('ads').remove([path]); // rollback upload
        rethrow;
      }
      if (mounted) {
        toast(context, 'Advertisement uploaded! It will appear on the display shortly.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) toast(context, 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chips(Map<String, String> options, String value, void Function(String) onPick) {
    return Wrap(
      spacing: 8,
      children: [
        for (final e in options.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: value == e.key,
            onSelected: (_) => setState(() => onPick(e.key)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add advertisement')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                      labelText: 'Advertisement title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                Text('1. Select age group', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _chips(ageLabels, _age, (v) => _age = v),
                const SizedBox(height: 20),
                Text('2. Select gender', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _chips(genderLabels, _gender, (v) => _gender = v),
                const SizedBox(height: 20),
                Text('3. Upload advertisement', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.upload_file),
                  label: Text(_file == null
                      ? 'Choose video / image (max 50 MB)'
                      : '${_file!.name}  (${(_file!.size / 1048576).toStringAsFixed(1)} MB)'),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _upload,
                    icon: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload),
                    label: Text(_busy ? 'Uploading...' : 'Publish advertisement'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}