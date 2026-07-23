import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import '../camera_session.dart';

/// The app's entry point: pick a camera, or set one up.
///
/// Deliberately first in the bottom nav, because every other tab operates on a
/// camera that must already be chosen — the setup-before-features ordering this
/// epic exists to establish.
///
/// **Contains no per-backend code.** Saved cameras are rendered from
/// [CameraSession.profiles], and the "Add camera" sheet renders one tile per
/// [CameraSetupWizardRegistry.registeredTypes] using each wizard's own
/// `displayName`/`icon`. Registering a tenth backend adds a tenth tile here
/// with no edit to this file. Likewise the per-camera **Edit** action appears
/// only when the registered wizard reports [CameraSetupWizard.supportsEditing] —
/// a capability query, not a backend-type check.
class CamerasTab extends StatelessWidget {
  const CamerasTab({super.key, required this.session, required this.wizards});

  final CameraSession session;
  final CameraSetupWizardRegistry wizards;

  Future<void> _addCamera(BuildContext context) async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => _AddCameraSheet(wizards: wizards),
    );
    if (type == null || !context.mounted) return;

    final wizard = wizards.create(type);
    final profile = await Navigator.of(context).push<CameraProfile>(
      MaterialPageRoute<CameraProfile>(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(title: Text(wizard.displayName)),
          body: wizard.build(
            routeContext,
            // The wizard guarantees exactly one of these fires, exactly once,
            // so a single pop per route is correct.
            onComplete: (profile) => Navigator.of(routeContext).pop(profile),
            onCancel: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    );
    if (profile == null) return;
    await session.saveAndSwitchTo(profile);
  }

  /// Whether a saved camera can be edited: asked of its **registered wizard**,
  /// never of its backend-type string, so this file still names no backend.
  /// A profile can outlive its backend's registration (an app build that no
  /// longer registers it), so the lookup is guarded rather than assumed.
  bool _canEdit(CameraProfile profile) =>
      wizards.isRegistered(profile.backendType) &&
      wizards.create(profile.backendType).supportsEditing;

  Future<void> _editCamera(BuildContext context, CameraProfile profile) async {
    final wizard = wizards.create(profile.backendType);
    final updated = await Navigator.of(context).push<CameraProfile>(
      MaterialPageRoute<CameraProfile>(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(title: Text(profile.displayName)),
          body: wizard.buildEditor(
            routeContext,
            profile: profile,
            // Same single-pop-per-callback contract as _addCamera.
            onComplete: (edited) => Navigator.of(routeContext).pop(edited),
            onCancel: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    );
    if (updated == null) return;
    await session.updateProfile(updated);
  }

  /// Renaming is backend-agnostic — [CameraProfile.displayName] is a plain label
  /// on the generic profile — so every saved camera offers it, including
  /// backends with no editor of their own.
  Future<void> _renameCamera(BuildContext context, CameraProfile profile) async {
    final controller = TextEditingController(text: profile.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename camera'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == profile.displayName) {
      return;
    }
    await session.updateProfile(profile.copyWith(displayName: trimmed));
  }

  Future<void> _confirmDelete(BuildContext context, CameraProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${profile.displayName}?'),
        content: const Text(
          'The saved settings and any stored password or verification code '
          'are deleted. The camera itself is untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await session.deleteProfile(profile.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final profiles = session.profiles;
        return Scaffold(
          body: profiles.isEmpty
              ? _EmptyState(busy: session.busy, error: session.error)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: profiles.length,
                  itemBuilder: (context, i) {
                    final profile = profiles[i];
                    return _ProfileTile(
                      profile: profile,
                      isActive: session.activeProfile?.id == profile.id,
                      isUnavailable:
                          session.unavailableProfileIds.contains(profile.id),
                      isOpen: session.isOpen,
                      busy: session.busy,
                      canEdit: _canEdit(profile),
                      onSelect: () => session.switchToProfile(profile),
                      onSetDefault: () => session.setDefaultProfile(profile.id),
                      onEdit: () => _editCamera(context, profile),
                      onRename: () => _renameCamera(context, profile),
                      onDelete: () => _confirmDelete(context, profile),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: session.busy ? null : () => _addCamera(context),
            icon: const Icon(Icons.add),
            label: const Text('Add camera'),
          ),
        );
      },
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.isActive,
    required this.isUnavailable,
    required this.isOpen,
    required this.busy,
    required this.canEdit,
    required this.onSelect,
    required this.onSetDefault,
    required this.onEdit,
    required this.onRename,
    required this.onDelete,
  });

  final CameraProfile profile;
  final bool isActive;
  final bool isUnavailable;
  final bool isOpen;
  final bool busy;
  final bool canEdit;
  final VoidCallback onSelect;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = profile.device.metadata['host'];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ListTile(
        leading: Icon(
          isActive && isOpen ? Icons.videocam : Icons.videocam_outlined,
          color: isUnavailable ? theme.colorScheme.outline : null,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                profile.displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isUnavailable ? theme.colorScheme.outline : null,
                ),
              ),
            ),
            if (profile.isDefault) ...[
              const SizedBox(width: 8),
              const _Badge(label: 'Default'),
            ],
            if (isUnavailable) ...[
              const SizedBox(width: 8),
              const _Badge(label: 'Not found'),
            ],
          ],
        ),
        subtitle: Text(
          host == null
              ? profile.backendType
              : '${profile.backendType} · $host',
        ),
        onTap: busy ? null : onSelect,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'default') onSetDefault();
            if (value == 'edit') onEdit();
            if (value == 'rename') onRename();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            if (!profile.isDefault)
              const PopupMenuItem<String>(
                value: 'default',
                child: Text('Open this one at startup'),
              ),
            if (canEdit)
              const PopupMenuItem<String>(
                value: 'edit',
                child: Text('Edit settings'),
              ),
            const PopupMenuItem<String>(
              value: 'rename',
              child: Text('Rename'),
            ),
            const PopupMenuItem<String>(
              value: 'delete',
              child: Text('Remove'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.busy, required this.error});

  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text(
              'No cameras set up yet.\n'
              'Add one to unlock the preview, scanner and PTZ tabs.',
              textAlign: TextAlign.center,
            ),
            if (busy) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The "Add camera" chooser: one tile per registered wizard.
///
/// The whole point of the wizard registry — this widget names no backend and
/// knows no backend's steps.
class _AddCameraSheet extends StatelessWidget {
  const _AddCameraSheet({required this.wizards});

  final CameraSetupWizardRegistry wizards;

  @override
  Widget build(BuildContext context) {
    final types = wizards.registeredTypes;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('What kind of camera?'),
          ),
          for (final type in types)
            Builder(
              builder: (context) {
                final wizard = wizards.create(type);
                return ListTile(
                  leading: Icon(wizard.icon),
                  title: Text(wizard.displayName),
                  onTap: () => Navigator.of(context).pop(type),
                );
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
