
source_module_map=$1
target_module_map=$2
relative_path=$3
swift_generated_header=$4
module_name=$5
module_map_content=`cat "$source_module_map"`
module_map_content=`echo "${module_map_content//framework module/module}"`
index=0
for arg in "$@"
do
   let index+=1
   if [ $index -gt 5 ]; then
        filename="$(basename "$arg")"
        module_map_content=`echo "${module_map_content//\"${filename}\"/\"${relative_path}${arg}\"}"`
   fi
done
if [ $swift_generated_header != "empty" ]; then
   swift_generated_header_content="\nmodule ${module_name}.Swift {\n  header \"${relative_path}${swift_generated_header}\"\n  requires objc\n}\n"
   module_map_content=`echo "${module_map_content}${swift_generated_header_content}"`
fi
echo "$module_map_content" > "$target_module_map"
