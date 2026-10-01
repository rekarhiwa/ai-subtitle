import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/subtitle_segment.dart';
import '../../widgets/studio_widgets.dart';
import '../settings/settings_screen.dart';
import '../subtitle_editor/subtitle_editor_screen.dart';

/// CapCut-style home: New project + drafts grid.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeControllerProvider);
    final controller = ref.read(homeControllerProvider.notifier);
    final apiKeyAsync = ref.watch(apiKeyProvider);
    final hasKey = (apiKeyAsync.asData?.value ?? '').isNotEmpty;

    ref.listen(homeControllerProvider, (prev, next) async {
      if (prev?.phase != ProcessingPhase.done &&
          next.phase == ProcessingPhase.done &&
          next.video != null &&
          next.segments.isNotEmpty) {
        await ref.read(editorControllerProvider.notifier).open(
              video: next.video!,
              segments: next.segments,
              projectId: next.projectId,
            );
        if (context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SubtitleEditorScreen(),
            ),
          );
          ref.read(homeControllerProvider.notifier).resetPhase();
        }
      }
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Projects',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  if (!hasKey)
                    TextButton(
                      onPressed: () => _openSettings(context),
                      child: const Text('API Key'),
                    ),
                  IconButton(
                    onPressed: () => _openSettings(context),
                    icon: const Icon(Icons.settings_outlined, size: 22),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _NewProjectCard(
                            busy: state.isBusy,
                            onImport: () =>
                                _pickVideo(context, ref, controller),
                          ),
                          if (state.video != null &&
                              state.phase != ProcessingPhase.idle) ...[
                            const SizedBox(height: 14),
                            SoftCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    state.video!.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (state.isBusy)
                                    LinearProgressIndicator(
                                      value: state.progress > 0.02
                                          ? state.progress
                                          : null,
                                      color: AppColors.playhead,
                                      backgroundColor: AppColors.surfaceSoft,
                                    ),
                                  const SizedBox(height: 8),
                                  Text(
                                    state.statusMessage.isNotEmpty
                                        ? state.statusMessage
                                        : 'Ready',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: state.isBusy
                                              ? null
                                              : () => _openEditor(
                                                    context,
                                                    ref,
                                                    segments: state.segments,
                                                  ),
                                          child: const Text('Open editor'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: state.isBusy
                                              ? null
                                              : () => controller
                                                  .generateSubtitles(),
                                          child: const Text('Auto captions'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          const Row(
                            children: [
                              Text(
                                'Drafts',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Spacer(),
                              Text(
                                AppConfig.appName,
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const _DraftsGrid(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    required List<SubtitleSegment> segments,
  }) async {
    final video = ref.read(homeControllerProvider).video;
    if (video == null) return;
    await ref.read(editorControllerProvider.notifier).open(
          video: video,
          segments: List.from(segments),
          projectId: ref.read(homeControllerProvider).projectId,
        );
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SubtitleEditorScreen(),
        ),
      );
    }
  }

  Future<void> _pickVideo(
    BuildContext context,
    WidgetRef ref,
    HomeController controller,
  ) async {
    HapticFeedback.mediumImpact();
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v'],
    );
    if (files.isEmpty) return;
    final path = files.first.path;
    if (path == null) return;
    try {
      await controller.selectVideo(path);
      if (!context.mounted) return;
      final video = ref.read(homeControllerProvider).video;
      if (video == null) return;
      await ref.read(editorControllerProvider.notifier).open(
            video: video,
            segments: const [],
            projectId: ref.read(homeControllerProvider).projectId,
          );
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SubtitleEditorScreen(),
        ),
      );
      ref.read(homeControllerProvider.notifier).resetPhase();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }
}

class _NewProjectCard extends StatelessWidget {
  const _NewProjectCard({required this.onImport, required this.busy});

  final VoidCallback onImport;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Material(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: busy ? null : onImport,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  busy ? Icons.hourglass_top_rounded : Icons.add_rounded,
                  color: Colors.black,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                busy ? 'Loading…' : 'New project',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Import video to start editing',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftsGrid extends ConsumerWidget {
  const _DraftsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentProjectsProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (projects) {
        if (projects.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 36),
            alignment: Alignment.center,
            child: const Text(
              'No drafts yet',
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: projects.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (context, i) {
            final project = projects[i];
            final thumb = project.primaryVideo.thumbnailPath;
            return Material(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  await ref
                      .read(editorControllerProvider.notifier)
                      .openProject(project);
                  if (context.mounted) {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SubtitleEditorScreen(),
                      ),
                    );
                    ref.invalidate(recentProjectsProvider);
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: thumb != null && File(thumb).existsSync()
                          ? Image.file(File(thumb), fit: BoxFit.cover)
                          : Container(
                              color: AppColors.surfaceSoft,
                              child: const Icon(
                                Icons.movie_outlined,
                                color: AppColors.textMuted,
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${project.captions.length} captions',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
