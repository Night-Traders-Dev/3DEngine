# test_forge_version.sage - Shared Forge Engine version helpers
# Run: ./run.sh tests/test_forge_version.sage

from forge_version import engine_name, engine_version, engine_banner
from forge_version import editor_title, editor_play_title, about_text, scene_format_version
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
check("engine banner includes version", engine_banner() == "Forge Engine v" + file_version)
check("editor title", editor_title() == "Forge Engine Editor")
check("editor play title", editor_play_title() == "Forge Engine Editor | PLAYING")

let about = about_text("Test GPU")
check("about text includes banner", contains(about, engine_banner()))
check("about text includes gpu", contains(about, "Test GPU"))
check("scene format version", scene_format_version() == 1)

print ""
print "Results: " + str(pass_count) + " passed, " + str(fail_count) + " failed"
if fail_count > 0:
    raise "Forge version sanity checks failed!"
else:
    print "All Forge version sanity checks passed!"
