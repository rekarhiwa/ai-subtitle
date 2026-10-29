import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/subtitle_segment.dart';
import '../../widgets/app_logo.dart';
import '../settings/settings_screen.dart';
import '../subtitle_editor/capcut_widgets.dart';
import '../subtitle_editor/subtitle_editor_screen.dart';

/// Montage home — Projects: New project + draft grid.
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
        final editorOpen =
            ref.read(editorControllerProvider.notifier).isRouteVisible;
        await ref.read(editorControllerProvider.notifier).open(
              video: next.video!,
              segments: next.segments,
              projectId: next.projectId,
            );
        if (!context.mounted) return;
        if (editorOpen) {
          ref.read(homeControllerProvider.notifier).resetPhase();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'ژێرنووس نوێکرایەوە',
                textDirection: TextDirection.rtl,
              ),
            ),
          );
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SubtitleEditorScreen(),
          ),
        );
        ref.read(homeControllerProvider.notifier).resetPhase();
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
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 4),
              child: Row(
                children: [
                  const AppLogo(size: 28, showWordmark: true, wordmarkSize: 17),
                  const Spacer(),
                  if (!hasKey)
                    GestureDetector(
                      onTap: () => _openSettings(context),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Text(
                          'API',
                          style: TextStyle(
                            color: AppColors.playhead,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: () => _openSettings(context),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.settings_outlined, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Projects',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.05,
                  ),
                ),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    sliver: SliverToBoxAdapter(
                      child: _NewProjectTile(
                        busy: state.isBusy,
                        onTap: () => _pickVideo(context, ref, controller),
                      ),
                    ),
                  ),
                  if (state.video != null &&
                      state.phase != ProcessingPhase.idle)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      sliver: SliverToBoxAdapter(
                        child: _ActiveJobBanner(
                          name: state.video!.fileName,
                          busy: state.isBusy,
                          progress: state.progress,
                          message: state.statusMessage,
                          onOpen: () => _openEditor(
                            context,
                            ref,
                            segments: state.segments,
                          ),
                          onCaptions: state.isBusy
                              ? null
                              : () => controller.generateSubtitles(),
                        ),
                      ),
                    ),
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Recent',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                    sliver: const _DraftsSliver(),
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

class _NewProjectTile extends StatelessWidget {
  const _NewProjectTile({required this.onTap, required this.busy});

  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          height: 156,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  busy ? Icons.hourglass_top_rounded : Icons.add_rounded,
                  color: Colors.black,
                  size: 28,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                busy ? 'Loading…' : 'New project',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Start from a video',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveJobBanner extends StatelessWidget {
  const _ActiveJobBanner({
    required this.name,
    required this.busy,
    required this.progress,
    required this.message,
    required this.onOpen,
    required this.onCaptions,
  });

  final String name;
  final bool busy;
  final double progress;
  final String message;
  final VoidCallback onOpen;
  final VoidCallback? onCaptions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: -0.2,
            ),
          ),
          if (busy) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress > 0.02 ? progress : null,
                minHeight: 2,
                color: AppColors.playhead,
                backgroundColor: AppColors.surfaceSoft,
              ),
            ),
          ],
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CapCutPillButton(
                  label: 'Edit',
                  filled: false,
                  expanded: true,
                  height: 36,
                  onPressed: busy ? null : onOpen,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CapCutPillButton(
                  label: 'Captions',
                  expanded: true,
                  height: 36,
                  onPressed: onCaptions,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DraftsSliver extends ConsumerWidget {
  const _DraftsSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentProjectsProvider);
    return async.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        ),
      ),
      error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (projects) {
        if (projects.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'No drafts yet',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.74,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final project = projects[i];
              final thumb = project.primaryVideo.thumbnailPath;
              final dur = project.primaryVideo.duration;
              final mins = dur.inMinutes;
              final secs = dur.inSeconds % 60;
              final durLabel =
                  '${mins.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
              return Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
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
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppRadius.sm),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              thumb != null && File(thumb).existsSync()
                                  ? Image.file(File(thumb), fit: BoxFit.cover)
                                  : Container(
                                      color: AppColors.surfaceElevated,
                                      child: const Icon(
                                        Icons.movie_outlined,
                                        color: AppColors.textMuted,
                                        size: 32,
                                      ),
                                    ),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    durLabel,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 7, 2, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              project.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${project.captions.length} captions',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500,
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
            childCount: projects.length,
          ),
        );
      },
    );
  }
}
