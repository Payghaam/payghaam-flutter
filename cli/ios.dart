import 'dart:io';

import 'log.dart';
import 'pbxproj.dart';
import 'plist.dart';
import 'podfile.dart';
import 'project.dart';

const nseName = 'PayghaamNSE';
const minIos = '15.0';

void configureIos(InstallProject project, InstallLog log,
    {String? appGroupFlag}) {
  final ios = project.iosDir;
  if (ios == null) {
    log.warn('No ios/ directory — skipping iOS');
    return;
  }

  log.section('iOS');

  final pbxFile = _findPbxproj(ios);
  if (pbxFile == null) {
    log.warn('Could not find ios/Runner.xcodeproj/project.pbxproj');
    return;
  }

  final pbx = PbxprojEditor(pbxFile.readAsStringSync());
  final bundleId = pbx.defaultBundleId();
  final appGroup = _resolveAppGroup(
    flag: appGroupFlag,
    pbx: pbx,
    ios: ios,
    bundleId: bundleId,
    log: log,
  );

  log.info('App Group: $appGroup');
  if (bundleId != null) {
    log.info('Bundle ID: $bundleId');
  }

  final deployment = _deploymentTarget(pbx);
  log.info('NSE deployment target: iOS $deployment');

  _ensureRunnerInfoPlist(ios, appGroup, log);
  _ensureRunnerEntitlements(ios, pbx, appGroup, log);
  _writeNseFiles(project, ios, appGroup, log);
  _updatePbxproj(pbxFile, pbx, deployment, log,
      hasPodfile: File('${ios.path}/Podfile').existsSync());
  _updatePodfile(ios, log);

  if (pbx.hasNseTarget || log.dryRun) {
    log.ok('Notification Service Extension target: $nseName');
  }

  log.remain(
    'Upload an APNs Auth Key (.p8) plus Key ID, Team ID, and Bundle ID in the '
    'Payghaam dashboard → Project → Channels → iOS · APNs.',
  );
  log.remain(
    'If Xcode signing fails, enable the App Group ($appGroup) for this App ID '
    'in the Apple Developer portal, then refresh provisioning.',
  );
  log.remain(
    "After login(), call shareConfig(appGroup: '$appGroup', apiBase: ..., apiKey: ..., externalId: ...).",
  );

  if (File('${ios.path}/Podfile').existsSync() && !log.dryRun) {
    log.remain(
      'Run `cd ios && pod install` (or `flutter build ios`) to pull Payghaam into $nseName.',
    );
  }
}

File? _findPbxproj(Directory ios) {
  final runner = File('${ios.path}/Runner.xcodeproj/project.pbxproj');
  if (runner.existsSync()) return runner;
  final projects = ios
      .listSync()
      .whereType<Directory>()
      .where((d) => d.path.endsWith('.xcodeproj'));
  for (final project in projects) {
    final pbx = File('${project.path}/project.pbxproj');
    if (pbx.existsSync()) return pbx;
  }
  return null;
}

String _resolveAppGroup({
  required String? flag,
  required PbxprojEditor pbx,
  required Directory ios,
  required String? bundleId,
  required InstallLog log,
}) {
  if (flag != null && flag.isNotEmpty) return flag;

  final info = File('${ios.path}/Runner/Info.plist');
  if (info.existsSync()) {
    final existing =
        PlistDoc(info.readAsStringSync()).stringValue('PayghaamAppGroup');
    if (existing != null && existing.isNotEmpty) {
      log.ok('Using existing PayghaamAppGroup from Info.plist');
      return existing;
    }
  }

  for (final rel in pbx.runnerEntitlementsPaths()) {
    final file = File('${ios.path}/$rel');
    if (!file.existsSync()) continue;
    for (final group in PlistDoc(file.readAsStringSync())
        .arrayStrings('com.apple.security.application-groups')) {
      if (group.endsWith('.payghaam')) {
        log.ok('Using existing App Group from entitlements');
        return group;
      }
    }
  }

  if (bundleId != null && bundleId.isNotEmpty) {
    return 'group.$bundleId.payghaam';
  }

  log.warn(
    'Could not detect a bundle ID; using group.app.payghaam. '
    'Re-run with --app-group=group.your.bundle.payghaam',
  );
  return 'group.app.payghaam';
}

String _deploymentTarget(PbxprojEditor pbx) {
  var best = minIos;
  final project = pbx.projectDeploymentTarget();
  if (project != null) best = maxIosVersion(best, project);
  for (final cfg in pbx.runnerConfigs()) {
    if (cfg.deploymentTarget != null) {
      best = maxIosVersion(best, cfg.deploymentTarget!);
    }
  }
  return best;
}

void _ensureRunnerInfoPlist(Directory ios, String appGroup, InstallLog log) {
  final file = File('${ios.path}/Runner/Info.plist');
  if (!file.existsSync()) {
    log.warn('Missing ios/Runner/Info.plist');
    return;
  }
  final doc = PlistDoc(file.readAsStringSync());
  var changed = false;
  if (doc.setString('PayghaamAppGroup', appGroup)) {
    changed = true;
    log.changedLine('Set PayghaamAppGroup in Runner/Info.plist');
  } else {
    log.ok('Runner/Info.plist already has PayghaamAppGroup');
  }
  if (doc.addArrayString('UIBackgroundModes', 'remote-notification')) {
    changed = true;
    log.changedLine(
        'Enabled Background Modes → remote-notification in Runner/Info.plist');
  } else {
    log.ok('Background Modes already includes remote-notification');
  }
  if (changed && !log.dryRun) {
    file.writeAsStringSync(doc.content);
  }
}

void _ensureRunnerEntitlements(
  Directory ios,
  PbxprojEditor pbx,
  String appGroup,
  InstallLog log,
) {
  var paths = pbx.runnerEntitlementsPaths();
  if (paths.isEmpty) {
    paths = ['Runner/Runner.entitlements'];
    if (pbx.ensureRunnerEntitlements('Runner/Runner.entitlements')) {
      log.changedLine('Set CODE_SIGN_ENTITLEMENTS on the Runner target');
    }
  }

  for (final rel in paths) {
    final file = File('${ios.path}/$rel');
    if (!file.existsSync()) {
      if (log.dryRun) {
        log.changedLine('Create $rel with Push + App Group');
        continue;
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entitlementsTemplate(appGroup: appGroup));
      log.changedLine('Created $rel (Push Notifications + App Group)');
      continue;
    }

    final doc = PlistDoc(file.readAsStringSync());
    var changed = false;
    if (!doc.hasKey('aps-environment')) {
      if (doc.setString('aps-environment', 'development')) {
        changed = true;
        log.changedLine('Added aps-environment (Push Notifications) to $rel');
      }
    } else {
      log.ok('$rel already has aps-environment');
    }
    if (doc.addArrayString('com.apple.security.application-groups', appGroup)) {
      changed = true;
      log.changedLine('Added App Group $appGroup to $rel');
    } else {
      log.ok('$rel already includes App Group $appGroup');
    }
    if (changed && !log.dryRun) {
      file.writeAsStringSync(doc.content);
    }
  }
}

void _writeNseFiles(
  InstallProject project,
  Directory ios,
  String appGroup,
  InstallLog log,
) {
  final dir = Directory('${ios.path}/$nseName');
  final swiftSrc = project.nseSwiftSource;
  if (!swiftSrc.existsSync()) {
    log.warn(
      'Package is missing ios_extension/NotificationService.swift at ${swiftSrc.path}',
    );
    return;
  }
  final swiftDest = File('${dir.path}/NotificationService.swift');
  final infoDest = File('${dir.path}/Info.plist');
  final entDest = File('${dir.path}/$nseName.entitlements');

  if (!log.dryRun) {
    dir.createSync(recursive: true);
  }

  _writeIfChanged(
    swiftDest,
    swiftSrc.readAsStringSync(),
    log,
    created: 'Copied NotificationService.swift into $nseName/',
    same: 'NotificationService.swift already matches the package template',
  );

  final info = infoDest.existsSync()
      ? PlistDoc(infoDest.readAsStringSync())
      : PlistDoc(nseInfoPlistTemplate(appGroup));
  if (!infoDest.existsSync()) {
    if (!log.dryRun) infoDest.writeAsStringSync(nseInfoPlistTemplate(appGroup));
    log.changedLine('Created $nseName/Info.plist');
  } else if (info.setString('PayghaamAppGroup', appGroup)) {
    if (!log.dryRun) infoDest.writeAsStringSync(info.content);
    log.changedLine('Set PayghaamAppGroup in $nseName/Info.plist');
  } else {
    log.ok('$nseName/Info.plist already has PayghaamAppGroup');
  }

  if (!entDest.existsSync()) {
    if (!log.dryRun) {
      entDest.writeAsStringSync(nseEntitlementsTemplate(appGroup));
    }
    log.changedLine('Created $nseName/$nseName.entitlements');
  } else {
    final doc = PlistDoc(entDest.readAsStringSync());
    if (doc.addArrayString('com.apple.security.application-groups', appGroup)) {
      if (!log.dryRun) entDest.writeAsStringSync(doc.content);
      log.changedLine('Added App Group to $nseName entitlements');
    } else {
      log.ok('$nseName entitlements already include App Group $appGroup');
    }
  }
}

void _writeIfChanged(
  File dest,
  String next,
  InstallLog log, {
  required String created,
  required String same,
}) {
  if (dest.existsSync() && dest.readAsStringSync() == next) {
    log.ok(same);
    return;
  }
  if (!log.dryRun) {
    dest.parent.createSync(recursive: true);
    dest.writeAsStringSync(next);
  }
  log.changedLine(created);
}

void _updatePbxproj(
  File pbxFile,
  PbxprojEditor pbx,
  String deployment,
  InstallLog log, {
  required bool hasPodfile,
}) {
  if (pbx.hasNseTarget) {
    log.ok('Xcode project already has the $nseName target');
  } else {
    final message = pbx.addNseTarget(
      deploymentTarget: deployment,
      entitlementsRelPath: '$nseName/$nseName.entitlements',
      infoPlistRelPath: '$nseName/Info.plist',
    );
    if (message != null) {
      log.changedLine(message);
    }
  }

  if (!hasPodfile) {
    final spm = pbx.ensurePayghaamSpm();
    if (spm != null) {
      log.changedLine(spm);
    } else {
      log.ok('Payghaam iOS SDK (Swift Package) already linked to $nseName');
    }
  }

  if (pbx.content != pbxFile.readAsStringSync()) {
    if (!log.dryRun) {
      pbxFile.writeAsStringSync(pbx.content);
    }
  }
}

void _updatePodfile(Directory ios, InstallLog log) {
  final file = File('${ios.path}/Podfile');
  if (!file.existsSync()) return;
  final result = ensurePayghaamNseTarget(file.readAsStringSync());
  if (!result.changed) {
    log.ok("Podfile already has target '$nseName'");
    return;
  }
  if (!log.dryRun) {
    file.writeAsStringSync(result.content);
  }
  log.changedLine(result.message!);
}
