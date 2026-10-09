import 'dart:typed_data';

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
  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _fileIsVideo =>
      _videoExt.contains((_file?.extension ?? '').toLowerCase());

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [..._videoExt, ..._imageExt],
      withData: true,
    );

    if (res == null || res.files.isEmpty) return;

    final f = res.files.first;

    if (f.size > _maxBytes) {
      if (mounted) {
        toast(
          context,
          'File is larger than 50 MB. Please compress it.',
        );
      }
      return;
    }

    setState(() => _file = f);
  }

  void _clearFile() => setState(() => _file = null);

  Future<void> _upload() async {
    final title = _title.text.trim();

    setState(
      () => _titleError =
          title.isEmpty ? 'Enter an advertisement title' : null,
    );

    if (title.isEmpty) return;

    if (_file == null || _file!.bytes == null) {
      toast(context, 'Choose a video or image file');
      return;
    }

    setState(() => _busy = true);

    final uid = supabase.auth.currentUser!.id;
    final ext = (_file!.extension ?? 'mp4').toLowerCase();
    final path =
        '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      await supabase.storage.from('ads').uploadBinary(
            path,
            _file!.bytes!,
            fileOptions: FileOptions(
              contentType:
                  _mime[ext] ?? 'application/octet-stream',
              upsert: false,
            ),
          );

      try {
        await supabase.from('ads').insert({
          'title': title,
          'age_group': _age,
          'gender': _gender,
          'file_path': path,
          'file_type':
              _videoExt.contains(ext) ? 'video' : 'image',
        });
      } catch (e) {
        await supabase.storage.from('ads').remove([path]);
        rethrow;
      }

      if (mounted) {
        toast(
          context,
          'Advertisement uploaded! It will appear on the display shortly.',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        toast(
          context,
          'Upload failed. Please check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sectionLabel(String number, String text) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3D6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFFF59E0B),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF101828),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _chips(
    Map<String, String> options,
    String value,
    void Function(String) onPick,
  ) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final e in options.entries)
          ChoiceChip(
            label: Text(
              e.value,
              style: TextStyle(
                color: value == e.key
                    ? const Color(0xFF101828)
                    : const Color(0xFF475467),
                fontWeight: value == e.key
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
            selected: value == e.key,
            showCheckmark: false,
            backgroundColor: const Color(0xFFF8FAFC),
            selectedColor: const Color(0xFFFFC44D),
            side: BorderSide(
              color: value == e.key
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFD0D5DD),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            onSelected: _busy
                ? null
                : (_) => setState(() => onPick(e.key)),
          ),
      ],
    );
  }

  Widget _filePreview() {
    final file = _file!;
    final isVideo = _fileIsVideo;
    final Uint8List? bytes = file.bytes;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD0D5DD),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 68,
              height: 68,
              child: !isVideo && bytes != null
                  ? Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: const Color(0xFFEFF2F6),
                      child: Icon(
                        isVideo
                            ? Icons.movie_outlined
                            : Icons.image_outlined,
                        color: const Color(0xFF475467),
                        size: 30,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Advertisement media',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(file.size / 1048576).toStringAsFixed(1)} MB'
                  '  •  ${isVideo ? 'Video' : 'Image'}',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFD92D20),
            ),
            tooltip: 'Remove file',
            onPressed: _busy ? null : _clearFile,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const darkNavy = Color(0xFF101828);
    const accent = Color(0xFFF59E0B);
    const background = Color(0xFFF8FAFC);

    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _busy) {
          toast(
            context,
            'Please wait for the upload to finish',
          );
        }
      },
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: darkNavy,
          foregroundColor: Colors.white,
          titleSpacing: 20,
          title: const Row(
            children: [
              Icon(
                Icons.campaign_rounded,
                color: accent,
                size: 25,
              ),
              SizedBox(width: 10),
              Text(
                'Create Advertisement',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 720,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      // =====================================================
                      // PAGE HEADER
                      // =====================================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: darkNavy,
                          borderRadius:
                              BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius:
                                    BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.ads_click_rounded,
                                color: darkNavy,
                                size: 29,
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Launch a new campaign',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight:
                                          FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 5),
                                  Text(
                                    'Create your advertisement and target '
                                    'the right audience.',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // =====================================================
                      // FORM CARD
                      // =====================================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFE4E7EC),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  Colors.black.withValues(alpha: 0.04),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            // =================================================
                            // ADVERTISEMENT TITLE
                            // =================================================
                            _sectionLabel(
                              '1',
                              'Advertisement details',
                            ),

                            const SizedBox(height: 14),

                            TextField(
                              controller: _title,
                              maxLength: 60,
                              enabled: !_busy,
                              style: const TextStyle(
                                color: darkNavy,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                labelText:
                                    'Advertisement title',
                                hintText:
                                    'e.g. Summer Sale 2026',
                                prefixIcon: const Icon(
                                  Icons.title_rounded,
                                ),
                                filled: true,
                                fillColor:
                                    const Color(0xFFF8FAFC),
                                errorText: _titleError,
                                counterStyle: const TextStyle(
                                  color: Color(0xFF98A2B3),
                                ),
                                labelStyle: const TextStyle(
                                  color: Color(0xFF667085),
                                ),
                                hintStyle: const TextStyle(
                                  color: Color(0xFF98A2B3),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD0D5DD),
                                  ),
                                ),
                                enabledBorder:
                                    OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD0D5DD),
                                  ),
                                ),
                                focusedBorder:
                                    OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: accent,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              onChanged: (_) {
                                if (_titleError != null) {
                                  setState(
                                    () => _titleError = null,
                                  );
                                }
                              },
                            ),

                            const SizedBox(height: 22),

                            // =================================================
                            // AGE
                            // =================================================
                            _sectionLabel(
                              '2',
                              'Select age group',
                            ),

                            const SizedBox(height: 5),

                            const Text(
                              'Choose the audience you want to reach.',
                              style: TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 12,
                              ),
                            ),

                            const SizedBox(height: 12),

                            _chips(
                              ageLabels,
                              _age,
                              (v) => _age = v,
                            ),

                            const SizedBox(height: 24),

                            // =================================================
                            // GENDER
                            // =================================================
                            _sectionLabel(
                              '3',
                              'Select gender',
                            ),

                            const SizedBox(height: 5),

                            const Text(
                              'Select the primary audience for this ad.',
                              style: TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 12,
                              ),
                            ),

                            const SizedBox(height: 12),

                            _chips(
                              genderLabels,
                              _gender,
                              (v) => _gender = v,
                            ),

                            const SizedBox(height: 24),

                            // =================================================
                            // MEDIA UPLOAD
                            // =================================================
                            _sectionLabel(
                              '4',
                              'Upload advertisement',
                            ),

                            const SizedBox(height: 5),

                            const Text(
                              'Upload an image or video up to 50 MB.',
                              style: TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 12,
                              ),
                            ),

                            const SizedBox(height: 12),

                            if (_file != null)
                              _filePreview()
                            else
                              InkWell(
                                borderRadius:
                                    BorderRadius.circular(16),
                                onTap:
                                    _busy ? null : _pick,
                                child: Container(
                                  width: double.infinity,
                                  padding:
                                      const EdgeInsets.symmetric(
                                    vertical: 30,
                                    horizontal: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBF2),
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(
                                        0xFFF5C15D,
                                      ),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 58,
                                        height: 58,
                                        decoration: BoxDecoration(
                                          color: accent,
                                          borderRadius:
                                              BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons
                                              .cloud_upload_rounded,
                                          color: darkNavy,
                                          size: 30,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      const Text(
                                        'Upload your advertisement',
                                        style: TextStyle(
                                          color: darkNavy,
                                          fontSize: 15,
                                          fontWeight:
                                              FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      const Text(
                                        'Choose an image or video file',
                                        style: TextStyle(
                                          color:
                                              Color(0xFF667085),
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      OutlinedButton(
                                        onPressed:
                                            _busy ? null : _pick,
                                        style:
                                            OutlinedButton.styleFrom(
                                          foregroundColor:
                                              darkNavy,
                                          side:
                                              const BorderSide(
                                            color: darkNavy,
                                          ),
                                          shape:
                                              RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'Choose file',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            const SizedBox(height: 28),

                            // =================================================
                            // PUBLISH BUTTON
                            // =================================================
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: FilledButton.icon(
                                onPressed:
                                    _busy ? null : _upload,
                                style: FilledButton.styleFrom(
                                  backgroundColor: darkNavy,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      darkNavy.withValues(
                                    alpha: 0.45,
                                  ),
                                  shape:
                                      RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                icon: _busy
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons
                                            .rocket_launch_rounded,
                                        size: 20,
                                      ),
                                label: Text(
                                  _busy
                                      ? 'Uploading...'
                                      : 'Publish advertisement',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight:
                                        FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 14),

                            // =================================================
                            // SECURITY / INFO
                            // =================================================
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F4F7),
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                              child: const Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 18,
                                    color: Color(0xFF667085),
                                  ),
                                  SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      'Your advertisement will be uploaded '
                                      'securely and made available for display '
                                      'after publishing.',
                                      style: TextStyle(
                                        color:
                                            Color(0xFF667085),
                                        fontSize: 11,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // =====================================================
                      // FOOTER
                      // =====================================================
                      const Center(
                        child: Text(
                          'SMART ADVERTISING  •  BETTER RESULTS',
                          style: TextStyle(
                            color: Color(0xFF98A2B3),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}