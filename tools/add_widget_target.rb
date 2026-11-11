# بيضيف هدف ويدجتس الأيفون (TaawanuWidgets) لمشروع Xcode. بيتشغل مرة واحدة من GitHub Actions، والنتيجة بتتحفظ في المستودع.
require 'xcodeproj'

path = 'ios/Runner.xcodeproj'
name = 'TaawanuWidgets'
proj = Xcodeproj::Project.open(path)
if proj.targets.any? { |t| t.name == name }
  puts 'target already exists'
  exit 0
end

runner = proj.targets.find { |t| t.name == 'Runner' }
target = proj.new_target(:app_extension, name, :ios, '15.0', nil, :swift)

group = proj.main_group.new_group(name, name)
swift = group.new_file('TaawanuWidgets.swift')
group.new_file('Info.plist')
group.new_file('TaawanuWidgets.entitlements')
xcconfig = group.new_file('Widgets.xcconfig')
target.add_file_references([swift])

target.build_configurations.each do |c|
  c.base_configuration_reference = xcconfig
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.taawanu.taawanu.widgets'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'TaawanuWidgets/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = 'TaawanuWidgets/TaawanuWidgets.entitlements'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['ENABLE_BITCODE'] = 'NO'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

runner.add_dependency(target)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
file = embed.add_file_reference(target.product_reference)
file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# لازم ييجي قبل سكريبتات Flutter (Thin Binary)، وإلا Xcode بيطلع "Cycle inside Runner".
thin = runner.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
runner.build_phases.move(embed, runner.build_phases.index(thin)) if thin

proj.save
puts "added #{name}: #{target.build_configurations.map(&:name).join(', ')}"
puts runner.build_phases.map { |p| p.respond_to?(:name) && p.name ? p.name : p.class.name.split('::').last }.join(' > ')
