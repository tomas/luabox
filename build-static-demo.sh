archives="luabox.a termbox/build/libtermbox.a /usr/lib/x86_64-linux-gnu/libluajit-5.1.a"
flags="-lm -no-pie -static"
includes="-I /usr/include/luajit-2.0/"
out="ui"

echo " --> Building deps"
sh build.sh
echo " --> Building"
# cc -Os -s demos/ui.lua.c $archives $flags $includes -o $out
../luastatic/luastatic.lua demos/ui.lua $archives $includes $flags
rm -f demos/ui.lua.c

echo " --> Stripping"
strip $out
# strip -S --strip-unneeded --remove-section=.note.gnu.gold-version --remove-section=.comment --remove-section=.note --remove-section=.note.gnu.build-id --remove-section=.note.ABI-tag $out

ls -l $out | awk '{print $5}'
echo "Outfile: ${out}"