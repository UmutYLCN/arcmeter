#!/usr/bin/env python3
"""Generate the dependency-free Xcode project. Uses only Python's standard library."""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(key, isa, **values):
    objects[ident(key)] = dict(isa=isa, **values)
    return Ref(ident(key))

class Ref(str):
    pass

def fmt(value, level=0):
    if isinstance(value, Ref): return str(value)
    if isinstance(value, dict):
        return '{\n' + ''.join('\t'*(level+1)+k+' = '+fmt(v, level+1)+';\n' for k,v in value.items())+'\t'*level+'}'
    if isinstance(value, list): return '(\n'+''.join('\t'*(level+1)+fmt(v, level+1)+',\n' for v in value)+'\t'*level+')'
    return '"'+str(value).replace('\\', '\\\\').replace('"', '\\"')+'"'

def ref(name): return Ref(ident(name))

def configs(name, base):
    configs = []
    for mode in ['Debug', 'Release']:
        settings = dict(base)
        settings.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode == 'Debug' else '-O')
        if mode == 'Debug': settings.update(ENABLE_TESTABILITY='YES', DEBUG_INFORMATION_FORMAT='dwarf', ONLY_ACTIVE_ARCH='YES')
        else: settings.update(DEBUG_INFORMATION_FORMAT='dwarf-with-dsym')
        configs.append(add(name+mode, 'XCBuildConfiguration', buildSettings=settings, name=mode))
    return add(name+'Configs', 'XCConfigurationList', buildConfigurations=configs,
               defaultConfigurationIsVisible='0', defaultConfigurationName='Release')

# actool writes only four sizes into the legacy AppIcon.icns, so rebuild it from the complete appiconset.
ICON_SCRIPT = ('set -eu; iconset="${TARGET_TEMP_DIR}/AppIcon.iconset"; rm -rf "$iconset"; mkdir -p "$iconset"; '
               'cp "${SRCROOT}"/App/Assets.xcassets/AppIcon.appiconset/icon_*.png "$iconset"/; '
               'iconutil -c icns "$iconset" -o "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/AppIcon.icns"')

products = []
sources = {}
WIDGET_FILES = ['Widget/QuotaWidget.swift', 'Widget/AIQuotaWidget.swift', 'Widget/OrbitTheme.swift', 'Widget/OrbitViews.swift',
                'Widget/LedgerView.swift', 'Widget/ProviderMarks.swift', 'Widget/StateIcons.swift', 'Widget/QuotaIntents.swift']
for path in ['App/AIQuotaWidgetApp.swift', 'App/QuotaReader.swift', 'Shared/SnapshotStore.swift'] + WIDGET_FILES + [
             'QuotaCore/Tests/QuotaCoreTests/QuotaDecoderTests.swift', 'QuotaCore/Tests/QuotaCoreTests/DisplayTests.swift', 'QuotaCore/Tests/QuotaCoreTests/QuotaRunnerPathTests.swift']:
    sources[path] = add(path, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=path, sourceTree='<group>')
fixture = add('Fixtures', 'PBXFileReference', lastKnownFileType='folder', path='QuotaCore/Tests/QuotaCoreTests/Fixtures', sourceTree='<group>')
assets = add('Assets', 'PBXFileReference', lastKnownFileType='folder.assetcatalog', path='App/Assets.xcassets', sourceTree='<group>')
package = add('Package', 'XCLocalSwiftPackageReference', relativePath='QuotaCore')

for name, product, kind, files, extra in [
    ('AIQuotaWidget', 'Arcmeter.app', 'application', ['App/AIQuotaWidgetApp.swift', 'App/QuotaReader.swift', 'Shared/SnapshotStore.swift'],
     dict(INFOPLIST_FILE='Config/App-Info.plist', PRODUCT_NAME='Arcmeter', PRODUCT_BUNDLE_IDENTIFIER='local.ai-quota-widget',
          ENABLE_APP_SANDBOX='NO', ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',
          MARKETING_VERSION='1.1', CURRENT_PROJECT_VERSION='8')),
    ('QuotaWidgetExtension', 'QuotaWidgetExtension.appex', 'app-extension', WIDGET_FILES + ['Shared/SnapshotStore.swift'],
     dict(INFOPLIST_FILE='Config/Widget-Info.plist', PRODUCT_BUNDLE_IDENTIFIER='local.ai-quota-widget.widget',
          CODE_SIGN_ENTITLEMENTS='Config/Widget.entitlements', ENABLE_APP_SANDBOX='YES',
          APPLICATION_EXTENSION_API_ONLY='YES', SKIP_INSTALL='YES',
          MARKETING_VERSION='1.1', CURRENT_PROJECT_VERSION='8')),
    ('QuotaCoreTests', 'QuotaCoreTests.xctest', 'bundle.unit-test', ['QuotaCore/Tests/QuotaCoreTests/QuotaDecoderTests.swift', 'QuotaCore/Tests/QuotaCoreTests/DisplayTests.swift', 'QuotaCore/Tests/QuotaCoreTests/QuotaRunnerPathTests.swift'],
     dict(GENERATE_INFOPLIST_FILE='YES', PRODUCT_BUNDLE_IDENTIFIER='local.ai-quota-widget.tests')),
]:
    product_ref = add(name+'Product', 'PBXFileReference', explicitFileType={'application':'wrapper.application','app-extension':'wrapper.app-extension','bundle.unit-test':'wrapper.cfbundle'}[kind],
                      path=product, sourceTree='BUILT_PRODUCTS_DIR')
    products.append(product_ref)
    source_phase = add(name+'Sources', 'PBXSourcesBuildPhase', buildActionMask='2147483647', files=[
        add(name+path, 'PBXBuildFile', fileRef=sources[path]) for path in files], runOnlyForDeploymentPostprocessing='0')
    dep = add(name+'CoreDep', 'XCSwiftPackageProductDependency', package=package, productName='QuotaCore')
    framework_phase = add(name+'Frameworks', 'PBXFrameworksBuildPhase', buildActionMask='2147483647',
                          files=[add(name+'CoreLink', 'PBXBuildFile', productRef=dep)], runOnlyForDeploymentPostprocessing='0')
    resources = [add(name+'Fixture', 'PBXBuildFile', fileRef=fixture)] if name == 'QuotaCoreTests' else []
    if name == 'AIQuotaWidget': resources = [add(name+'Assets', 'PBXBuildFile', fileRef=assets)]
    resource_phase = add(name+'Resources', 'PBXResourcesBuildPhase', buildActionMask='2147483647', files=resources, runOnlyForDeploymentPostprocessing='0')
    phases = [source_phase, framework_phase, resource_phase]
    dependencies = []
    if name == 'AIQuotaWidget':
        phases.append(add('AppIconIcnsPhase', 'PBXShellScriptBuildPhase', buildActionMask='2147483647', files=[], inputPaths=[], outputPaths=[],
                          runOnlyForDeploymentPostprocessing='0', shellPath='/bin/sh', shellScript=ICON_SCRIPT, showEnvVarsInLog='0', alwaysOutOfDate='1', name='Build full AppIcon.icns'))
        embed = add('EmbedExtensionFile', 'PBXBuildFile', fileRef=ref('QuotaWidgetExtensionProduct'), settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
        phases.append(add('EmbedExtensions', 'PBXCopyFilesBuildPhase', buildActionMask='2147483647', dstPath='', dstSubfolderSpec='13', files=[embed], name='Embed App Extensions', runOnlyForDeploymentPostprocessing='0'))
        proxy = add('ExtensionProxy', 'PBXContainerItemProxy', containerPortal=ref('Project'), proxyType='1', remoteGlobalIDString=ref('QuotaWidgetExtensionTarget'), remoteInfo='QuotaWidgetExtension')
        dependencies.append(add('ExtensionDependency', 'PBXTargetDependency', target=ref('QuotaWidgetExtensionTarget'), targetProxy=proxy))
    settings = dict(PRODUCT_NAME='$(TARGET_NAME)', GENERATE_INFOPLIST_FILE='YES', CODE_SIGN_STYLE='Manual',
                    CODE_SIGN_IDENTITY='-', CODE_SIGNING_ALLOWED='YES', COMBINE_HIDPI_IMAGES='YES',
                    LD_RUNPATH_SEARCH_PATHS=['$(inherited)', '@executable_path/../Frameworks', '@executable_path/../../../../Frameworks'])
    settings.update(extra)
    add(name+'Target', 'PBXNativeTarget', buildConfigurationList=configs(name, settings), buildPhases=phases,
        buildRules=[], dependencies=dependencies, name=name, packageProductDependencies=[dep], productName=name,
        productReference=product_ref, productType='com.apple.product-type.'+kind)

product_group = add('Products', 'PBXGroup', children=products, name='Products', sourceTree='<group>')
main_group = add('MainGroup', 'PBXGroup', children=list(sources.values())+[fixture, assets, product_group], sourceTree='<group>')
project_config = configs('Project', dict(MACOSX_DEPLOYMENT_TARGET='15.0', SDKROOT='macosx', SWIFT_VERSION='6.0',
    CLANG_ENABLE_MODULES='YES', SWIFT_STRICT_CONCURRENCY='complete', ENABLE_HARDENED_RUNTIME='NO',
    COPY_PHASE_STRIP='NO', CURRENT_PROJECT_VERSION='1', MARKETING_VERSION='1.0', SUPPORTED_PLATFORMS='macosx'))
add('Project', 'PBXProject', attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2630'},
    buildConfigurationList=project_config, compatibilityVersion='Xcode 14.0', developmentRegion='en', hasScannedForEncodings='0',
    knownRegions=['en','Base'], mainGroup=main_group, productRefGroup=product_group, projectDirPath='', projectRoot='',
    packageReferences=[package], targets=[ref(name+'Target') for name in ['AIQuotaWidget','QuotaWidgetExtension','QuotaCoreTests']])
output = '// !$*UTF8*$!\n'+fmt(dict(archiveVersion='1', classes={}, objectVersion='60', objects=objects, rootObject=ref('Project')))+'\n'
(ROOT/'AIQuotaWidget.xcodeproj/project.pbxproj').write_text(output)

app = ident('AIQuotaWidgetTarget')
tests = ident('QuotaCoreTestsTarget')
(ROOT/'AIQuotaWidget.xcodeproj/xcshareddata/xcschemes/AIQuotaWidget.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2630" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="Arcmeter.app" BlueprintName="AIQuotaWidget" ReferencedContainer="container:AIQuotaWidget.xcodeproj"/>
    </BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{tests}" BuildableName="QuotaCoreTests.xctest" BlueprintName="QuotaCoreTests" ReferencedContainer="container:AIQuotaWidget.xcodeproj"/>
    </TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="Arcmeter.app" BlueprintName="AIQuotaWidget" ReferencedContainer="container:AIQuotaWidget.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
