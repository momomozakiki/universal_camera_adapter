import 'package:flutter/material.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import '../adapter_types.dart';
import '../ezviz/ezviz_wizard_flow.dart';

/// Setup flow for EZVIZ cloud cameras.
///
/// A thin adapter over [EzvizWizardFlow], which owns the actual steps (sign in
/// with the user's own EZVIZ account, list that account's devices, collect a
/// verification code for encrypted ones). This class's only job is turning the
/// chosen device into a persistable [CameraProfile] and putting the code
/// somewhere safe.
///
/// EZVIZ is registered as its own backend type alongside ONVIF rather than
/// folded into it: the same physical camera can be reached either way, but the
/// *setup* differs completely — a cloud account and verification code here, an
/// IP address and password there.
class EzvizSetupWizard extends CameraSetupWizard {
  EzvizSetupWizard({required this.secretStore});

  final CameraSecretStore secretStore;

  @override
  String get backendType => kEzvizAdapterType;

  @override
  String get displayName => 'EZVIZ (cloud)';

  @override
  IconData get icon => Icons.cloud_outlined;

  @override
  Widget build(
    BuildContext context, {
    required ValueChanged<CameraProfile> onComplete,
    required VoidCallback onCancel,
  }) {
    var finished = false;

    return EzvizWizardFlow(
      onCancel: () {
        if (finished) return;
        finished = true;
        onCancel();
      },
      onDeviceChosen: (device, verificationCode) async {
        if (finished) return;

        // The flow already proved the account and device are real: sign-in
        // succeeded and this device came back from the account's own device
        // list. That is this backend's connectivity check — the SDK gates it
        // before the user can reach this point.
        //
        // `device.metadata` here holds only advisory fields (brand,
        // isSupportPTZ, cameraNum); the verification code is deliberately not
        // among them, so the profile is secret-free by construction.
        final profile = CameraProfile.create(
          backendType: kEzvizAdapterType,
          displayName: device.name,
          device: device,
        );

        // Write the secret BEFORE completing. If this throws, the flow catches
        // it and shows the message, and neither callback fires — so the caller
        // never persists a profile whose verification code is unreachable.
        if (verificationCode != null) {
          await secretStore.setSecret(
            profile.id,
            kEzvizVerificationCodeSecretKey,
            verificationCode,
          );
        }

        finished = true;
        onComplete(profile);
      },
    );
  }
}
