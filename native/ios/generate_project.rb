require "xcodeproj"

Dir.chdir(__dir__) do
  project = Xcodeproj::Project.new("FinancialTracker.xcodeproj")
  target = project.new_target(:application, "FinancialTracker", :ios, "16.0")
  group = project.main_group.new_group("FinancialTracker", "FinancialTracker")
  %w[AppDelegate.swift SceneDelegate.swift].each do |name|
    target.source_build_phase.add_file_reference(group.new_file(name))
  end
  target.resources_build_phase.add_file_reference(group.new_file("path-configuration.json"))
  group.new_file("Info.plist")

  hotwire = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  hotwire.repositoryURL = "https://github.com/hotwired/hotwire-native-ios"
  hotwire.requirement = { "kind" => "exactVersion", "version" => "1.3.1" }
  project.root_object.package_references << hotwire
  policy = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  policy.relative_path = "URLPolicy"
  project.root_object.package_references << policy

  [[hotwire, "HotwireNative"], [policy, "DevelopmentURLPolicy"]].each do |reference, name|
    dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dependency.package = reference
    dependency.product_name = name
    target.package_product_dependencies << dependency
    build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    build_file.product_ref = dependency
    target.frameworks_build_phase.files << build_file
  end

  target.build_configurations.each do |config|
    config.build_settings.merge!(
      "PRODUCT_BUNDLE_IDENTIFIER" => "dev.financialtracker.shell",
      "INFOPLIST_FILE" => "FinancialTracker/Info.plist",
      "SWIFT_VERSION" => "6.0",
      "TARGETED_DEVICE_FAMILY" => "1,2",
      "CODE_SIGN_STYLE" => "Automatic",
      "IPHONEOS_DEPLOYMENT_TARGET" => "16.0"
    )
  end

  tests = project.new_target(:ui_test_bundle, "FinancialTrackerSmokeTests", :ios, "16.0")
  tests.add_dependency(target)
  tests_group = project.main_group.new_group("SmokeTests", "SmokeTests")
  tests.source_build_phase.add_file_reference(tests_group.new_file("PublicFixtureNavigationTests.swift"))
  tests.build_configurations.each do |config|
    config.build_settings.merge!(
      "PRODUCT_BUNDLE_IDENTIFIER" => "dev.financialtracker.shell.smoketests",
      "GENERATE_INFOPLIST_FILE" => "YES",
      "TEST_TARGET_NAME" => "FinancialTracker",
      "SWIFT_VERSION" => "6.0",
      "TARGETED_DEVICE_FAMILY" => "1,2",
      "IPHONEOS_DEPLOYMENT_TARGET" => "16.0",
      "CODE_SIGN_STYLE" => "Automatic"
    )
  end

  project.save
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)
  scheme.set_launch_target(target)
  scheme.add_test_target(tests)
  scheme.save_as(project.path, "FinancialTracker", true)

  rails_tests = project.new_target(:ui_test_bundle, "FinancialTrackerRailsSmokeTests", :ios, "16.0")
  rails_tests.add_dependency(target)
  rails_group = project.main_group.new_group("RailsSmokeTests", "RailsSmokeTests")
  rails_tests.source_build_phase.add_file_reference(rails_group.new_file("RealRailsSessionTests.swift"))
  rails_tests.build_configurations.each do |config|
    config.build_settings.merge!(
      "PRODUCT_BUNDLE_IDENTIFIER" => "dev.financialtracker.shell.railssmoketests",
      "GENERATE_INFOPLIST_FILE" => "YES",
      "TEST_TARGET_NAME" => "FinancialTracker",
      "SWIFT_VERSION" => "6.0",
      "TARGETED_DEVICE_FAMILY" => "1,2",
      "IPHONEOS_DEPLOYMENT_TARGET" => "16.0",
      "CODE_SIGN_STYLE" => "Automatic"
    )
  end
  project.save
  rails_scheme = Xcodeproj::XCScheme.new
  rails_scheme.add_build_target(target)
  rails_scheme.set_launch_target(target)
  rails_scheme.add_test_target(rails_tests)
  rails_scheme.save_as(project.path, "FinancialTrackerRailsSmoke", true)
end
