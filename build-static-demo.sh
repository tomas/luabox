archives="luabox.a termbox/build/libtermbox.a /usr/lib/x86_64-linux-gnu/libluajit-5.1.a"
flags="-lm -no-pie -static"
includes="-I /usr/include/luajit-2.0/"
out="layout"
deps="demos/lib/ui.lua demos/lib/classic.lua demos/lib/events.lua"

echo " --> Building deps"
sh build.sh

rm -f "$out"
echo " --> Building ${out}"
# cc -Os -s demos/ui.lua.c $archives $flags $includes -o $out
../luastatic/luastatic.lua demos/layout.lua $deps $archives $includes $flags

# rm -f demos/layout.lua.c

echo " --> Stripping"
strip $out
# strip -S --strip-unneeded --remove-section=.note.gnu.gold-version --remove-section=.comment --remove-section=.note --remove-section=.note.gnu.build-id --remove-section=.note.ABI-tag $out

ls -l $out | awk '{print $5}'
echo "Outfile: ${out}"