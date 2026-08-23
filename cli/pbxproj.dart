import 'dart:math';

const nseTargetName = 'PayghaamNSE';

class RunnerConfig {
  RunnerConfig({
    required this.id,
    required this.name,
    required this.bundleId,
    this.team,
    this.entitlements,
    this.deploymentTarget,
    this.codeSignStyle,
  });

  final String id;
  final String name;
  final String? bundleId;
  final String? team;
  final String? entitlements;
  final String? deploymentTarget;
  final String? codeSignStyle;
}

class PbxprojEditor {
  PbxprojEditor(this.content);

  String content;
  final _rng = Random();

  bool get hasNseTarget =>
      RegExp('name = $nseTargetName;').hasMatch(content) ||
      content.contains('/* $nseTargetName */');

  Set<String> get usedIds {
    return RegExp(r'\b[A-F0-9]{24}\b')
        .allMatches(content)
        .map((m) => m.group(0)!)
        .toSet();
  }

  String newId() {
    const hex = '0123456789ABCDEF';
    final used = usedIds;
    String id;
    do {
      id = List.generate(24, (_) => hex[_rng.nextInt(16)]).join();
    } while (used.contains(id));
    return id;
  }

  String? get projectId {
    final match = RegExp(r'rootObject = ([A-F0-9]{24})').firstMatch(content);
    return match?.group(1);
  }

  String? get appTargetId {
    final targets = _nativeTargets();
    for (final t in targets) {
      if (t.name == 'Runner' && t.productType.contains('application')) {
        return t.id;
      }
    }
    for (final t in targets) {
      if (t.productType.contains('application')) return t.id;
    }
    return null;
  }

  List<RunnerConfig> runnerConfigs() {
    final targetId = appTargetId;
    if (targetId == null) return const [];
    final target = _objectBody(targetId);
    if (target == null) return const [];
    final listId = RegExp(r'buildConfigurationList = ([A-F0-9]{24})')
        .firstMatch(target)
        ?.group(1);
    if (listId == null) return const [];
    final list = _objectBody(listId);
    if (list == null) return const [];
    final configIds = RegExp(r'([A-F0-9]{24}) /\*')
        .allMatches(list)
        .map((m) => m.group(1)!)
        .toList();
    final out = <RunnerConfig>[];
    for (final id in configIds) {
      final body = _objectBody(id);
      if (body == null) continue;
      if (!body.contains('isa = XCBuildConfiguration')) continue;
      final name = _setting(body, 'name') ?? _commentName(id) ?? id;
      out.add(
        RunnerConfig(
          id: id,
          name: _unquote(name),
          bundleId: _opt(_setting(body, 'PRODUCT_BUNDLE_IDENTIFIER')),
          team: _opt(_setting(body, 'DEVELOPMENT_TEAM')),
          entitlements: _opt(_setting(body, 'CODE_SIGN_ENTITLEMENTS')),
          deploymentTarget: _opt(_setting(body, 'IPHONEOS_DEPLOYMENT_TARGET')),
          codeSignStyle: _opt(_setting(body, 'CODE_SIGN_STYLE')),
        ),
      );
    }
    return out;
  }

  String? projectDeploymentTarget() {
    final id = projectId;
    if (id == null) return null;
    final project = _objectBody(id);
    if (project == null) return null;
    final listId = RegExp(r'buildConfigurationList = ([A-F0-9]{24})')
        .firstMatch(project)
        ?.group(1);
    if (listId == null) return null;
    final list = _objectBody(listId);
    if (list == null) return null;
    for (final m in RegExp(r'([A-F0-9]{24}) /\*').allMatches(list)) {
      final body = _objectBody(m.group(1)!);
      if (body == null) continue;
      final v = _setting(body, 'IPHONEOS_DEPLOYMENT_TARGET');
      if (v != null) return _unquote(v);
    }
    return null;
  }

  List<String> runnerEntitlementsPaths() {
    return runnerConfigs()
        .map((c) => c.entitlements)
        .whereType<String>()
        .toSet()
        .toList();
  }

  String? defaultBundleId() {
    for (final c in runnerConfigs()) {
      final id = c.bundleId;
      if (id == null || id.contains('\$')) continue;
      if (id.toLowerCase().contains('test') && runnerConfigs().length > 1) {
        continue;
      }
      return id;
    }
    for (final c in runnerConfigs()) {
      if (c.bundleId != null && !c.bundleId!.contains('\$')) return c.bundleId;
    }
    return null;
  }

  /// Sets CODE_SIGN_ENTITLEMENTS on Runner configs that don't already have one.
  bool ensureRunnerEntitlements(String relativePath) {
    var changed = false;
    for (final config in runnerConfigs()) {
      if (config.entitlements != null && config.entitlements!.isNotEmpty) {
        continue;
      }
      if (_setBuildSetting(config.id, 'CODE_SIGN_ENTITLEMENTS', relativePath)) {
        changed = true;
      }
    }
    return changed;
  }

  /// Creates the PayghaamNSE app-extension target and wires it into Runner.
  /// Returns a human-readable message, or null if the target already exists.
  String? addNseTarget({
    required String deploymentTarget,
    required String entitlementsRelPath,
    required String infoPlistRelPath,
  }) {
    if (hasNseTarget) return null;

    final runnerId = appTargetId;
    final projId = projectId;
    if (runnerId == null || projId == null) {
      throw StateError(
          'Could not find the Runner application target in project.pbxproj');
    }

    final configs = runnerConfigs();
    if (configs.isEmpty) {
      throw StateError(
          'Could not read Runner build configurations from project.pbxproj');
    }

    final swiftRef = newId();
    final plistRef = newId();
    final entitlementsRef = newId();
    final appexRef = newId();
    final swiftBuild = newId();
    final embedBuild = newId();
    final groupId = newId();
    final sourcesId = newId();
    final frameworksId = newId();
    final resourcesId = newId();
    final targetId = newId();
    final configListId = newId();
    final proxyId = newId();
    final depId = newId();
    final embedPhaseId = newId();
    final configIds = {for (final c in configs) c.name: newId()};

    _insertInSection('PBXBuildFile', '''
		$swiftBuild /* NotificationService.swift in Sources */ = {isa = PBXBuildFile; fileRef = $swiftRef /* NotificationService.swift */; };
		$embedBuild /* $nseTargetName.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = $appexRef /* $nseTargetName.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
''');

    _insertInSection('PBXContainerItemProxy', '''
		$proxyId /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = $projId /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = $targetId;
			remoteInfo = $nseTargetName;
		};
''');

    var embedPhase = _findEmbedExtensionsPhaseId();
    if (embedPhase == null) {
      embedPhase = embedPhaseId;
      _insertInSection('PBXCopyFilesBuildPhase', '''
		$embedPhaseId /* Embed Foundation Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				$embedBuild /* $nseTargetName.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
''');
      _addToParenList(runnerId, 'buildPhases',
          '\t\t\t\t$embedPhaseId /* Embed Foundation Extensions */,');
    } else {
      _addToParenList(
        embedPhase,
        'files',
        '\t\t\t\t$embedBuild /* $nseTargetName.appex in Embed Foundation Extensions */,',
      );
    }

    _insertInSection('PBXFileReference', '''
		$swiftRef /* NotificationService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NotificationService.swift; sourceTree = "<group>"; };
		$plistRef /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		$entitlementsRef /* $nseTargetName.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = $nseTargetName.entitlements; sourceTree = "<group>"; };
		$appexRef /* $nseTargetName.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = $nseTargetName.appex; sourceTree = BUILT_PRODUCTS_DIR; };
''');

    _insertInSection('PBXFrameworksBuildPhase', '''
		$frameworksId /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
''');

    _insertInSection('PBXGroup', '''
		$groupId /* $nseTargetName */ = {
			isa = PBXGroup;
			children = (
				$swiftRef /* NotificationService.swift */,
				$plistRef /* Info.plist */,
				$entitlementsRef /* $nseTargetName.entitlements */,
			);
			path = $nseTargetName;
			sourceTree = "<group>";
		};
''');

    final mainGroupId = _idSetting(_objectBody(projId) ?? '', 'mainGroup');
    if (mainGroupId != null) {
      _addToParenList(
          mainGroupId, 'children', '\t\t\t\t$groupId /* $nseTargetName */,');
    }
    final productsGroupId =
        _idSetting(_objectBody(projId) ?? '', 'productRefGroup');
    if (productsGroupId != null) {
      _addToParenList(
        productsGroupId,
        'children',
        '\t\t\t\t$appexRef /* $nseTargetName.appex */,',
      );
    }

    _insertInSection('PBXNativeTarget', '''
		$targetId /* $nseTargetName */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = $configListId /* Build configuration list for PBXNativeTarget "$nseTargetName" */;
			buildPhases = (
				$sourcesId /* Sources */,
				$frameworksId /* Frameworks */,
				$resourcesId /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = $nseTargetName;
			packageProductDependencies = (
			);
			productName = $nseTargetName;
			productReference = $appexRef /* $nseTargetName.appex */;
			productType = "com.apple.product-type.app-extension";
		};
''');

    _addToParenList(
        projId, 'targets', '\t\t\t\t$targetId /* $nseTargetName */,');
    _addToParenList(
        runnerId, 'dependencies', '\t\t\t\t$depId /* PBXTargetDependency */,');

    _insertInSection('PBXResourcesBuildPhase', '''
		$resourcesId /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
''');

    _insertInSection('PBXSourcesBuildPhase', '''
		$sourcesId /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				$swiftBuild /* NotificationService.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
''');

    _insertInSection('PBXTargetDependency', '''
		$depId /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = $targetId /* $nseTargetName */;
			targetProxy = $proxyId /* PBXContainerItemProxy */;
		};
''');

    final configBlocks = StringBuffer();
    final configListEntries = StringBuffer();
    for (final cfg in configs) {
      final id = configIds[cfg.name]!;
      final bundle = (cfg.bundleId != null && !cfg.bundleId!.contains(r'$'))
          ? '${cfg.bundleId}.$nseTargetName'
          : '\$(PRODUCT_BUNDLE_IDENTIFIER).$nseTargetName';
      final teamLine =
          cfg.team != null ? '\t\t\t\tDEVELOPMENT_TEAM = ${cfg.team};\n' : '';
      final styleLine = cfg.codeSignStyle != null
          ? '\t\t\t\tCODE_SIGN_STYLE = ${cfg.codeSignStyle};\n'
          : '\t\t\t\tCODE_SIGN_STYLE = Automatic;\n';
      final debugExtras = cfg.name.toLowerCase().contains('debug')
          ? '\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";\n'
          : '';
      final quotedName = cfg.name.contains('-') || cfg.name.contains(' ')
          ? '"${cfg.name}"'
          : cfg.name;
      configBlocks.writeln('''
		$id /* ${cfg.name} */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = $entitlementsRelPath;
$styleLine\t\t\t\tCURRENT_PROJECT_VERSION = 1;
$teamLine\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = $infoPlistRelPath;
				IPHONEOS_DEPLOYMENT_TARGET = $deploymentTarget;
				LD_RUNPATH_SEARCH_PATHS = (
					"\$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = $bundle;
				PRODUCT_NAME = "\$(TARGET_NAME)";
				SKIP_INSTALL = YES;
$debugExtras\t\t\t\tSWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = $quotedName;
		};''');
      configListEntries.writeln('\t\t\t\t$id /* ${cfg.name} */,');
    }

    _insertInSection('XCBuildConfiguration', configBlocks.toString());

    final defaultName =
        configs.any((c) => c.name == 'Release') ? 'Release' : configs.last.name;
    final quotedDefault =
        defaultName.contains('-') ? '"$defaultName"' : defaultName;
    _insertInSection('XCConfigurationList', '''
		$configListId /* Build configuration list for PBXNativeTarget "$nseTargetName" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
$configListEntries\t\t\t);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = $quotedDefault;
		};
''');

    return 'Created $nseTargetName Notification Service Extension target';
  }

  /// Adds the published Payghaam iOS SDK as an SPM dependency of PayghaamNSE.
  /// Used when the host app has no CocoaPods Podfile.
  String? ensurePayghaamSpm({
    String url = 'https://github.com/payghaam/payghaam-ios.git',
    String minimumVersion = '0.1.0',
  }) {
    String? nseId;
    for (final t in _nativeTargets()) {
      if (t.name == nseTargetName) {
        nseId = t.id;
        break;
      }
    }
    if (nseId == null) return null;

    var packageRefId = RegExp(
      r'([A-F0-9]{24}) /\* XCRemoteSwiftPackageReference "payghaam-ios" \*/',
    ).firstMatch(content)?.group(1);

    var created = false;
    if (packageRefId == null) {
      packageRefId = newId();
      _insertInSection('XCRemoteSwiftPackageReference', '''
		$packageRefId /* XCRemoteSwiftPackageReference "payghaam-ios" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "$url";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = $minimumVersion;
			};
		};
''');
      if (projectId != null) {
        final proj = _objectBody(projectId!) ?? '';
        if (proj.contains('packageReferences = (')) {
          _addToParenList(
            projectId!,
            'packageReferences',
            '\t\t\t\t$packageRefId /* XCRemoteSwiftPackageReference "payghaam-ios" */,',
          );
        }
      }
      created = true;
    }

    var productId = RegExp(
      r'([A-F0-9]{24}) /\* Payghaam \*/ = \{\s*isa = XCSwiftPackageProductDependency;',
    ).firstMatch(content)?.group(1);

    if (productId == null) {
      productId = newId();
      _insertInSection('XCSwiftPackageProductDependency', '''
		$productId /* Payghaam */ = {
			isa = XCSwiftPackageProductDependency;
			package = $packageRefId /* XCRemoteSwiftPackageReference "payghaam-ios" */;
			productName = Payghaam;
		};
''');
      created = true;
    }

    final nseBody = _objectBody(nseId) ?? '';
    if (nseBody.contains(productId)) {
      return created
          ? 'Added Payghaam iOS SDK (Swift Package) to the Xcode project'
          : null;
    }

    if (nseBody.contains('packageProductDependencies = (')) {
      _addToParenList(
        nseId,
        'packageProductDependencies',
        '\t\t\t\t$productId /* Payghaam */,',
      );
    } else {
      final range = _objectRange(nseId);
      if (range != null) {
        final insert =
            '\t\t\tpackageProductDependencies = (\n\t\t\t\t$productId /* Payghaam */,\n\t\t\t);\n';
        // Place it before productName.
        final body = content.substring(range.start, range.end);
        final idx = body.indexOf('productName =');
        if (idx >= 0) {
          final at = range.start + idx;
          content =
              '${content.substring(0, at)}$insert${content.substring(at)}';
        }
      }
    }
    return 'Added Payghaam iOS SDK (Swift Package) to $nseTargetName';
  }

  String? _findEmbedExtensionsPhaseId() {
    final match = RegExp(
      r'([A-F0-9]{24}) /\* Embed Foundation Extensions \*/ = \{\s*isa = PBXCopyFilesBuildPhase',
    ).firstMatch(content);
    return match?.group(1);
  }

  void _insertInSection(String section, String objects) {
    final end = '/* End $section section */';
    if (content.contains(end)) {
      content = content.replaceFirst(end, '$objects$end');
      return;
    }
    final begin =
        '/* Begin $section section */\n$objects/* End $section section */\n\n';
    const anchor = '/* Begin XCBuildConfiguration section */';
    if (content.contains(anchor)) {
      content = content.replaceFirst(anchor, '$begin$anchor');
      return;
    }
    // Last resort: before the closing of the objects dict.
    final objectsClose = content.lastIndexOf('\t};');
    if (objectsClose < 0) {
      throw StateError('Could not find a place to insert the $section section');
    }
    content =
        '${content.substring(0, objectsClose)}$begin${content.substring(objectsClose)}';
  }

  bool _addToParenList(String objectId, String key, String entryLine) {
    final range = _objectRange(objectId);
    if (range == null) return false;
    final body = content.substring(range.start, range.end);
    final entryId = RegExp(r'[A-F0-9]{24}').firstMatch(entryLine)?.group(0);
    if (entryId != null && body.contains(entryId)) {
      return false;
    }
    final keyMatch = RegExp('$key = \\(').firstMatch(body);
    if (keyMatch == null) return false;
    final open = range.start + keyMatch.end - 1;
    final close = _matching(content, open, '(', ')');
    if (close < 0) return false;
    final prefix = content.substring(0, close);
    final insertion = prefix.endsWith('\n') ? '$entryLine\n' : '\n$entryLine\n';
    content = '$prefix$insertion${content.substring(close)}';
    return true;
  }

  bool _setBuildSetting(String configId, String key, String value) {
    final body = _objectBody(configId);
    if (body == null) return false;
    if (RegExp('$key = [^;]+;').hasMatch(body)) return false;
    final range = _objectRange(configId);
    if (range == null) return false;
    final settings = RegExp(r'buildSettings = \{').firstMatch(body);
    if (settings == null) return false;
    final open = range.start + settings.end - 1;
    final insertAt = open + 1;
    final line = '\n\t\t\t\t$key = $value;';
    content =
        '${content.substring(0, insertAt)}$line${content.substring(insertAt)}';
    return true;
  }

  String? _objectBody(String id) {
    final range = _objectRange(id);
    if (range == null) return null;
    return content.substring(range.start, range.end);
  }

  _Range? _objectRange(String id) {
    final pattern = RegExp('\n\t\t$id(?: /\\* .*? \\*/)? = \\{');
    final match = pattern.firstMatch(content);
    if (match == null) return null;
    final open = match.end - 1;
    final close = _matching(content, open, '{', '}');
    if (close < 0) return null;
    return _Range(match.start + 1, close + 1);
  }

  List<_NativeTarget> _nativeTargets() {
    final out = <_NativeTarget>[];
    for (final m in RegExp(
      r'([A-F0-9]{24}) /\* ([^*]+) \*/ = \{\s*isa = PBXNativeTarget;',
    ).allMatches(content)) {
      final id = m.group(1)!;
      final body = _objectBody(id) ?? '';
      final name = _unquote(_setting(body, 'name') ?? m.group(2)!.trim());
      final productType = _unquote(_setting(body, 'productType') ?? '');
      out.add(_NativeTarget(id: id, name: name, productType: productType));
    }
    return out;
  }

  String? _setting(String body, String key) {
    final match = RegExp('$key = ([^;\\n]+);').firstMatch(body);
    return match?.group(1)?.trim();
  }

  String? _idSetting(String body, String key) {
    return RegExp('$key = ([A-F0-9]{24})').firstMatch(body)?.group(1);
  }

  String? _commentName(String id) {
    return RegExp('$id /\\* ([^*]+) \\*/')
        .firstMatch(content)
        ?.group(1)
        ?.trim();
  }

  String _unquote(String? raw) {
    if (raw == null) return '';
    var v = raw.trim();
    if (v.startsWith('"') && v.endsWith('"') && v.length >= 2) {
      v = v.substring(1, v.length - 1);
    }
    return v;
  }

  String? _opt(String? raw) {
    final v = _unquote(raw);
    return v.isEmpty ? null : v;
  }

  int _matching(String s, int openIndex, String open, String close) {
    var depth = 0;
    var inString = false;
    for (var i = openIndex; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (c == '"' && (i == 0 || s[i - 1] != '\\')) inString = false;
        continue;
      }
      if (c == '"') {
        inString = true;
        continue;
      }
      if (c == open) depth++;
      if (c == close) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }
}

class _Range {
  _Range(this.start, this.end);
  final int start;
  final int end;
}

class _NativeTarget {
  _NativeTarget({
    required this.id,
    required this.name,
    required this.productType,
  });
  final String id;
  final String name;
  final String productType;
}

String maxIosVersion(String a, String b) {
  List<int> parts(String v) =>
      v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final pa = parts(a);
  final pb = parts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va > vb) return a;
    if (vb > va) return b;
  }
  return a;
}
