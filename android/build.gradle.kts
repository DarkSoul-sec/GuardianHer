allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// flutter_secure_storage 11.x hardcodes compileSdk = 37, but this toolchain
// (AGP 9.1.0 / sdklib 32.1.0) cannot resolve an "android-37" target (its
// platform hash is "android-37.0"). Compile that plugin at 36 instead; it
// compiles cleanly there and runs fine on devices at targetSdk 36.
subprojects {
    afterEvaluate {
        if (name == "flutter_secure_storage") {
            val androidExt = extensions.findByName("android")
            if (androidExt is com.android.build.api.dsl.LibraryExtension) {
                androidExt.compileSdk = 36
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}