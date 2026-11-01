import Foundation

enum Fixture {
    /// A folder of its own for one test, removed with the process's temporary files.
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("localize-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `files` (relative path → text) under `folder`.
    static func write(_ files: [String: String], in folder: URL) throws {
        for (path, text) in files {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// A recipe app as `granite` lays one out: a synchronized-folders project, two app targets, a few SwiftUI views.
    static func kitchen() throws -> URL {
        let folder = try folder()
        var files = kitchenSwift
        files["Kitchen.xcodeproj/project.pbxproj"] = project
        files["Kitchen.xcodeproj/xcshareddata/xcschemes/Kitchen-iOS.xcscheme"] = scheme(target: "170000000000000000000001", name: "Kitchen-iOS")
        files["Kitchen.xcodeproj/xcshareddata/xcschemes/Kitchen-macOS.xcscheme"] = scheme(target: "170000000000000000000002", name: "Kitchen-macOS")
        try write(files, in: folder)
        return folder
    }

    /// The keys the recipe app's Swift asks for, as the runtime asks for them.
    static let kitchenKeys: Set<String> = [
        "Saved %lld recipes", "Cooked by %@ in %lld minutes", "Recipes", "Favorites", "Vegetarian only", "Recipe name", "Filters",
        "%lld recipes", "Search recipes", "Clear All", "Removes every recipe from the list", "Remove every recipe?", "Remove", "Cancel",
        "This cannot be undone.", "Quick", "Slow cook", "RECIPES_EMPTY_TITLE", "Add a recipe to see it here.\nIt stays on this device.",
        "Starter", "Main course", "Dessert", "Course", "New", "Share Recipe",
    ]

    static let kitchenSwift: [String: String] = [
        "Shared/App.swift": #"""
        import SwiftUI

        @main
        struct KitchenApp: App {
            init() {
                // `--strings` prints a few strings as the person's language reads them, then quits.
                if CommandLine.arguments.contains("--strings") {
                    let count = 3
                    let cook = "Ada"
                    let minutes = 20
                    print(String(localized: "Saved \(count) recipes", comment: "A message after recipes are saved"))
                    print(String(localized: "Cooked by \(cook) in \(minutes) minutes"))
                    print(String(localized: "Recipes"))
                    exit(0)
                }
            }

            var body: some Scene {
                WindowGroup {
                    RecipeList()
                }
            }
        }
        """#,
        "Shared/Recipe.swift": #"""
        import Foundation

        struct Recipe: Identifiable, Hashable {
            let id: Int
            var title: String
            var minutes: Int
            var cook: String
            var isNew: Bool

            static let samples = [
                Recipe(id: 1, title: "Tomato soup", minutes: 25, cook: "Ada", isNew: true),
                Recipe(id: 2, title: "Bean stew", minutes: 90, cook: "Grace", isNew: false),
            ]
        }
        """#,
        "Shared/Course.swift": #"""
        import SwiftUI

        enum Course: String, CaseIterable, Identifiable {
            case starter, main, dessert

            var id: Self { self }

            var title: LocalizedStringKey {
                switch self {
                case .starter: return "Starter"
                case .main: return "Main course"
                case .dessert: return "Dessert"
                }
            }
        }
        """#,
        "Shared/Views/Badge.swift": #"""
        import SwiftUI

        struct Badge: View {
            let title: LocalizedStringKey

            var body: some View {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        """#,
        "Shared/Views/EmptyPantry.swift": #"""
        import SwiftUI

        struct EmptyPantry: View {
            var body: some View {
                ContentUnavailableView {
                    Label("RECIPES_EMPTY_TITLE", systemImage: "fork.knife")
                } description: {
                    Text("Add a recipe to see it here.\nIt stays on this device.")
                }
            }
        }
        """#,
        "Components/RecipeList/RecipeList.swift": #"""
        import SwiftUI

        struct RecipeList: View {
            @State private var recipes = Recipe.samples
            @State private var query = ""
            @State private var vegetarianOnly = false
            @State private var course = Course.main
            @State private var confirmingClear = false

            var body: some View {
                NavigationStack {
                    List {
                        Section("Favorites") {
                            ForEach(recipes) { recipe in
                                RecipeRow(recipe: recipe)
                            }
                        }
                        Section {
                            Toggle("Vegetarian only", isOn: $vegetarianOnly)
                            TextField("Recipe name", text: $query)
                            Picker("Course", selection: $course) {
                                ForEach(Course.allCases) { course in
                                    Text(course.title).tag(course)
                                }
                            }
                        } header: {
                            Text("Filters", comment: "The header above the list's filters")
                        }
                        Text("\(recipes.count) recipes")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(verbatim: "v1.0")
                        Text("•")
                        if recipes.isEmpty {
                            EmptyPantry()
                        }
                    }
                    .navigationTitle("Recipes")
                    .searchable(text: $query, prompt: "Search recipes")
                    .toolbar {
                        ToolbarItem {
                            ShareRecipeButton()
                        }
                        ToolbarItem {
                            Button("Clear All", systemImage: "trash") { confirmingClear = true }
                                .help("Removes every recipe from the list")
                        }
                    }
                    .alert("Remove every recipe?", isPresented: $confirmingClear) {
                        Button("Remove", role: .destructive) { recipes = [] }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This cannot be undone.")
                    }
                }
            }
        }

        #Preview {
            Text("Preview only")
        }
        """#,
        "Components/RecipeList/RecipeRow.swift": #"""
        import SwiftUI

        struct RecipeRow: View {
            let recipe: Recipe

            var body: some View {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(recipe.title)
                            .font(.headline)
                        if recipe.isNew {
                            Badge(title: "New")
                        }
                    }
                    Text("Cooked by \(recipe.cook) in \(recipe.minutes) minutes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(recipe.minutes < 30 ? "Quick" : "Slow cook", systemImage: "clock")
                        .font(.caption)
                }
                .accessibilityElement(children: .combine)
            }
        }
        """#,
        "iOS/ShareRecipeButton.swift": #"""
        import SwiftUI

        struct ShareRecipeButton: View {
            var body: some View {
                Button("Share Recipe", systemImage: "square.and.arrow.up") {}
            }
        }
        """#,
        "macOS/ShareRecipeButton.swift": #"""
        import SwiftUI

        struct ShareRecipeButton: View {
            var body: some View {
                Button("Share Recipe", systemImage: "square.and.arrow.up") {}
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        """#,
    ]

    /// The recipe app's project: objectVersion 77, synchronized Shared, Components, iOS and macOS, no packages.
    static let project = #"""
    // !$*UTF8*$!
    {
    	archiveVersion = 1;
    	classes = {
    	};
    	objectVersion = 77;
    	objects = {

    /* Begin PBXFileReference section */
    		130000000000000000000001 /* Kitchen.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Kitchen.app; sourceTree = BUILT_PRODUCTS_DIR; };
    		130000000000000000000002 /* Kitchen.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Kitchen.app; sourceTree = BUILT_PRODUCTS_DIR; };
    /* End PBXFileReference section */

    /* Begin PBXFileSystemSynchronizedRootGroup section */
    		140000000000000000000001 /* Shared */ = {
    			isa = PBXFileSystemSynchronizedRootGroup;
    			path = Shared;
    			sourceTree = "<group>";
    		};
    		140000000000000000000002 /* iOS */ = {
    			isa = PBXFileSystemSynchronizedRootGroup;
    			path = iOS;
    			sourceTree = "<group>";
    		};
    		140000000000000000000003 /* macOS */ = {
    			isa = PBXFileSystemSynchronizedRootGroup;
    			path = macOS;
    			sourceTree = "<group>";
    		};
    		140000000000000000000004 /* Components */ = {
    			isa = PBXFileSystemSynchronizedRootGroup;
    			path = Components;
    			sourceTree = "<group>";
    		};
    /* End PBXFileSystemSynchronizedRootGroup section */

    /* Begin PBXFrameworksBuildPhase section */
    		150000000000000000000001 /* Frameworks */ = {
    			isa = PBXFrameworksBuildPhase;
    			buildActionMask = 2147483647;
    			files = (
    			);
    			runOnlyForDeploymentPostprocessing = 0;
    		};
    		150000000000000000000002 /* Frameworks */ = {
    			isa = PBXFrameworksBuildPhase;
    			buildActionMask = 2147483647;
    			files = (
    			);
    			runOnlyForDeploymentPostprocessing = 0;
    		};
    /* End PBXFrameworksBuildPhase section */

    /* Begin PBXGroup section */
    		160000000000000000000001 = {
    			isa = PBXGroup;
    			children = (
    				140000000000000000000001 /* Shared */,
    				140000000000000000000004 /* Components */,
    				140000000000000000000002 /* iOS */,
    				140000000000000000000003 /* macOS */,
    				160000000000000000000002 /* Products */,
    			);
    			sourceTree = "<group>";
    		};
    		160000000000000000000002 /* Products */ = {
    			isa = PBXGroup;
    			children = (
    				130000000000000000000001 /* Kitchen.app */,
    				130000000000000000000002 /* Kitchen.app */,
    			);
    			name = Products;
    			sourceTree = "<group>";
    		};
    /* End PBXGroup section */

    /* Begin PBXNativeTarget section */
    		170000000000000000000001 /* Kitchen-iOS */ = {
    			isa = PBXNativeTarget;
    			buildConfigurationList = 180000000000000000000002 /* Build configuration list for PBXNativeTarget "Kitchen-iOS" */;
    			buildPhases = (
    				190000000000000000000001 /* Sources */,
    				150000000000000000000001 /* Frameworks */,
    				1A0000000000000000000001 /* Resources */,
    			);
    			buildRules = (
    			);
    			dependencies = (
    			);
    			fileSystemSynchronizedGroups = (
    				140000000000000000000001 /* Shared */,
    				140000000000000000000004 /* Components */,
    				140000000000000000000002 /* iOS */,
    			);
    			name = "Kitchen-iOS";
    			productName = Kitchen;
    			productReference = 130000000000000000000001 /* Kitchen.app */;
    			productType = "com.apple.product-type.application";
    		};
    		170000000000000000000002 /* Kitchen-macOS */ = {
    			isa = PBXNativeTarget;
    			buildConfigurationList = 180000000000000000000003 /* Build configuration list for PBXNativeTarget "Kitchen-macOS" */;
    			buildPhases = (
    				190000000000000000000002 /* Sources */,
    				150000000000000000000002 /* Frameworks */,
    				1A0000000000000000000002 /* Resources */,
    			);
    			buildRules = (
    			);
    			dependencies = (
    			);
    			fileSystemSynchronizedGroups = (
    				140000000000000000000001 /* Shared */,
    				140000000000000000000004 /* Components */,
    				140000000000000000000003 /* macOS */,
    			);
    			name = "Kitchen-macOS";
    			productName = Kitchen;
    			productReference = 130000000000000000000002 /* Kitchen.app */;
    			productType = "com.apple.product-type.application";
    		};
    /* End PBXNativeTarget section */

    /* Begin PBXProject section */
    		1B0000000000000000000001 /* Project object */ = {
    			isa = PBXProject;
    			attributes = {
    				BuildIndependentTargetsInParallel = 1;
    				LastSwiftUpdateCheck = 2660;
    				LastUpgradeCheck = 2660;
    			};
    			buildConfigurationList = 180000000000000000000001 /* Build configuration list for PBXProject "Kitchen" */;
    			developmentRegion = en;
    			hasScannedForEncodings = 0;
    			knownRegions = (
    				en,
    				Base,
    			);
    			mainGroup = 160000000000000000000001;
    			minimizedProjectReferenceProxies = 1;
    			preferredProjectObjectVersion = 77;
    			productRefGroup = 160000000000000000000002 /* Products */;
    			projectDirPath = "";
    			projectRoot = "";
    			targets = (
    				170000000000000000000001 /* Kitchen-iOS */,
    				170000000000000000000002 /* Kitchen-macOS */,
    			);
    		};
    /* End PBXProject section */

    /* Begin PBXResourcesBuildPhase section */
    		1A0000000000000000000001 /* Resources */ = {
    			isa = PBXResourcesBuildPhase;
    			buildActionMask = 2147483647;
    			files = (
    			);
    			runOnlyForDeploymentPostprocessing = 0;
    		};
    		1A0000000000000000000002 /* Resources */ = {
    			isa = PBXResourcesBuildPhase;
    			buildActionMask = 2147483647;
    			files = (
    			);
    			runOnlyForDeploymentPostprocessing = 0;
    		};
    /* End PBXResourcesBuildPhase section */

    /* Begin PBXSourcesBuildPhase section */
    		190000000000000000000001 /* Sources */ = {
    			isa = PBXSourcesBuildPhase;
    			buildActionMask = 2147483647;
    			files = (
    			);
    			runOnlyForDeploymentPostprocessing = 0;
    		};
    		190000000000000000000002 /* Sources */ = {
    			isa = PBXSourcesBuildPhase;
    			buildActionMask = 2147483647;
    			files = (
    			);
    			runOnlyForDeploymentPostprocessing = 0;
    		};
    /* End PBXSourcesBuildPhase section */

    /* Begin XCBuildConfiguration section */
    		1D0000000000000000000001 /* Debug */ = {
    			isa = XCBuildConfiguration;
    			buildSettings = {
    				ALWAYS_SEARCH_USER_PATHS = NO;
    				CLANG_ENABLE_MODULES = YES;
    				CLANG_ENABLE_OBJC_ARC = YES;
    				DEBUG_INFORMATION_FORMAT = dwarf;
    				ENABLE_TESTABILITY = YES;
    				GCC_OPTIMIZATION_LEVEL = 0;
    				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
    				ONLY_ACTIVE_ARCH = YES;
    				SDKROOT = auto;
    				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
    				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
    			};
    			name = Debug;
    		};
    		1D0000000000000000000002 /* Release */ = {
    			isa = XCBuildConfiguration;
    			buildSettings = {
    				ALWAYS_SEARCH_USER_PATHS = NO;
    				CLANG_ENABLE_MODULES = YES;
    				CLANG_ENABLE_OBJC_ARC = YES;
    				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
    				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
    				SDKROOT = auto;
    				SWIFT_COMPILATION_MODE = wholemodule;
    			};
    			name = Release;
    		};
    		1D0000000000000000000003 /* Debug */ = {
    			isa = XCBuildConfiguration;
    			buildSettings = {
    				CURRENT_PROJECT_VERSION = 1;
    				GENERATE_INFOPLIST_FILE = YES;
    				INFOPLIST_KEY_CFBundleDisplayName = Kitchen;
    				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
    				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
    				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
    				LD_RUNPATH_SEARCH_PATHS = (
    					"$(inherited)",
    					"@executable_path/Frameworks",
    				);
    				MARKETING_VERSION = 1.0;
    				PRODUCT_BUNDLE_IDENTIFIER = nyc.rao.kitchen;
    				PRODUCT_NAME = Kitchen;
    				SDKROOT = iphoneos;
    				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
    				SWIFT_EMIT_LOC_STRINGS = YES;
    				SWIFT_VERSION = 5.0;
    				TARGETED_DEVICE_FAMILY = "1,2";
    			};
    			name = Debug;
    		};
    		1D0000000000000000000004 /* Release */ = {
    			isa = XCBuildConfiguration;
    			buildSettings = {
    				CURRENT_PROJECT_VERSION = 1;
    				GENERATE_INFOPLIST_FILE = YES;
    				INFOPLIST_KEY_CFBundleDisplayName = Kitchen;
    				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
    				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
    				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
    				LD_RUNPATH_SEARCH_PATHS = (
    					"$(inherited)",
    					"@executable_path/Frameworks",
    				);
    				MARKETING_VERSION = 1.0;
    				PRODUCT_BUNDLE_IDENTIFIER = nyc.rao.kitchen;
    				PRODUCT_NAME = Kitchen;
    				SDKROOT = iphoneos;
    				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
    				SWIFT_EMIT_LOC_STRINGS = YES;
    				SWIFT_VERSION = 5.0;
    				TARGETED_DEVICE_FAMILY = "1,2";
    			};
    			name = Release;
    		};
    		1D0000000000000000000005 /* Debug */ = {
    			isa = XCBuildConfiguration;
    			buildSettings = {
    				COMBINE_HIDPI_IMAGES = YES;
    				CURRENT_PROJECT_VERSION = 1;
    				GENERATE_INFOPLIST_FILE = YES;
    				INFOPLIST_KEY_CFBundleDisplayName = Kitchen;
    				LD_RUNPATH_SEARCH_PATHS = (
    					"$(inherited)",
    					"@executable_path/../Frameworks",
    				);
    				MACOSX_DEPLOYMENT_TARGET = 14.0;
    				MARKETING_VERSION = 1.0;
    				PRODUCT_BUNDLE_IDENTIFIER = nyc.rao.kitchen;
    				PRODUCT_NAME = Kitchen;
    				SDKROOT = macosx;
    				SWIFT_EMIT_LOC_STRINGS = YES;
    				SWIFT_VERSION = 5.0;
    			};
    			name = Debug;
    		};
    		1D0000000000000000000006 /* Release */ = {
    			isa = XCBuildConfiguration;
    			buildSettings = {
    				COMBINE_HIDPI_IMAGES = YES;
    				CURRENT_PROJECT_VERSION = 1;
    				GENERATE_INFOPLIST_FILE = YES;
    				INFOPLIST_KEY_CFBundleDisplayName = Kitchen;
    				LD_RUNPATH_SEARCH_PATHS = (
    					"$(inherited)",
    					"@executable_path/../Frameworks",
    				);
    				MACOSX_DEPLOYMENT_TARGET = 14.0;
    				MARKETING_VERSION = 1.0;
    				PRODUCT_BUNDLE_IDENTIFIER = nyc.rao.kitchen;
    				PRODUCT_NAME = Kitchen;
    				SDKROOT = macosx;
    				SWIFT_EMIT_LOC_STRINGS = YES;
    				SWIFT_VERSION = 5.0;
    			};
    			name = Release;
    		};
    /* End XCBuildConfiguration section */

    /* Begin XCConfigurationList section */
    		180000000000000000000001 /* Build configuration list for PBXProject "Kitchen" */ = {
    			isa = XCConfigurationList;
    			buildConfigurations = (
    				1D0000000000000000000001 /* Debug */,
    				1D0000000000000000000002 /* Release */,
    			);
    			defaultConfigurationIsVisible = 0;
    			defaultConfigurationName = Release;
    		};
    		180000000000000000000002 /* Build configuration list for PBXNativeTarget "Kitchen-iOS" */ = {
    			isa = XCConfigurationList;
    			buildConfigurations = (
    				1D0000000000000000000003 /* Debug */,
    				1D0000000000000000000004 /* Release */,
    			);
    			defaultConfigurationIsVisible = 0;
    			defaultConfigurationName = Release;
    		};
    		180000000000000000000003 /* Build configuration list for PBXNativeTarget "Kitchen-macOS" */ = {
    			isa = XCConfigurationList;
    			buildConfigurations = (
    				1D0000000000000000000005 /* Debug */,
    				1D0000000000000000000006 /* Release */,
    			);
    			defaultConfigurationIsVisible = 0;
    			defaultConfigurationName = Release;
    		};
    /* End XCConfigurationList section */
    	};
    	rootObject = 1B0000000000000000000001 /* Project object */;
    }

    """#

    /// A shared scheme that builds and runs one app target.
    static func scheme(target: String, name: String) -> String {
        #"""
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion = "2660" version = "1.7">
           <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
              <BuildActionEntries>
                 <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
                    <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "\#(target)" BuildableName = "Kitchen.app" BlueprintName = "\#(name)" ReferencedContainer = "container:Kitchen.xcodeproj">
                    </BuildableReference>
                 </BuildActionEntry>
              </BuildActionEntries>
           </BuildAction>
           <LaunchAction buildConfiguration = "Debug" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
              <BuildableProductRunnable runnableDebuggingMode = "0">
                 <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "\#(target)" BuildableName = "Kitchen.app" BlueprintName = "\#(name)" ReferencedContainer = "container:Kitchen.xcodeproj">
                 </BuildableReference>
              </BuildableProductRunnable>
           </LaunchAction>
        </Scheme>
        """#
    }
}
