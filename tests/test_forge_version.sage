# test_forge_version.sage - Shared Forge Engine version helpers
# Run: ./run.sh tests/test_forge_version.sage

from forge_version import engine_name, engine_version, engine_banner
from forge_version import editor_title, editor_play_title, about_text, scene_format_version
from forge_version import is_semver, is_engine_version_semver, is_pre_1_0_release, version_policy_text
import io

let pass_count = 0
let fail_count = 0

proc check(name, condition):
    if condition:
        pass_count = pass_count + 1
    else:
        print "  FAIL: " + name
        fail_count = fail_count + 1

print "=== Forge Version Sanity Checks ==="

let raw_version = io.readfile("VERSION")
let file_version = ""
if raw_version != nil:
    file_version = strip(raw_version)

check("version file exists", raw_version != nil)
check("version file has content", file_version != "")
check("engine name", engine_name() == "Forge Engine")
check("engine version matches file", engine_version() == file_version)
check("engine version is semver", is_engine_version_semver())
check("semver helper accepts current version", is_semver(file_version))
check("semver helper rejects short version", is_semver("0.6") == false)
check("semver helper rejects prefixed version", is_semver("v0.6.0") == false)
check("semver helper rejects leading zero token", is_semver("0.06.0") == false)
check("engine banner includes version", engine_banner() == "Forge Engine v" + file_version)
check("editor title", editor_title() == "Forge Engine Editor")
check("editor play title", editor_play_title() == "Forge Engine Editor | PLAYING")
check("pre-1.0 release policy", is_pre_1_0_release())
check("policy text is pre-1.0", version_policy_text() == "pre-1.0.0 development release")

let about = about_text("Test GPU")
check("about text includes banner", contains(about, engine_banner()))
check("about text includes policy", contains(about, "pre-1.0.0 development release"))
check("about text includes gpu", contains(about, "Test GPU"))
check("scene format version", scene_format_version() == 1)

print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Forge version sanity checks failed!"
else:
    print "All Forge version sanity checks passed!"
