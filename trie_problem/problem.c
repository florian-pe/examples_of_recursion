#include <stdio.h>
#include <glib.h>
#include <json-glib/json-glib.h>

// crepl: pkg-config --cflags --libs glib-2.0 json-glib-1.0
// gcc $(pkg-config --cflags --libs glib-2.0 json-glib-1.0) file.c -o file.o 
// ./file.o

int main (int argc, char * argv[]) {

    char* path_list[] = {"dir1/file1.txt","file2.txt","dir1/file3.txt","dir2/file4.txt"};
    GHashTable *root = g_hash_table_new(g_str_hash, g_str_equal);
    GHashTable *ptr;

    for (int i=0; i < sizeof(path_list)/sizeof(path_list[0]); i++) {

        ptr = root;
        gchar** path = g_strsplit(path_list[i], "/", 0);

        for (int j=0; j < g_strv_length(path); j++) {

            if (g_hash_table_contains(ptr, path[j])) {
            }
            else {
                GHashTable *hash = g_hash_table_new(g_str_hash, g_str_equal);
                g_hash_table_insert(ptr, path[j], hash);
            }
            ptr = g_hash_table_lookup(ptr, path[j]);
        }
    }

    JsonNode* make_json(gpointer file) {

        guint size = g_hash_table_size(file);
        gpointer* keys = g_hash_table_get_keys_as_array(file, &size);

        JsonArray* array = json_array_new();

        for (int i=0; i < size; i++) {

            char* key = keys[i];

            JsonObject* object = json_object_new();

            json_object_set_string_member(object, "name", key);

            JsonNode* array_node_ret = make_json(g_hash_table_lookup(file, key));
            JsonArray* array_ret = json_node_get_array(array_node_ret);
            json_object_set_array_member(object, "children", array_ret);

            JsonNode* elem = json_node_new(JSON_NODE_OBJECT);
            json_node_set_object(elem, object);

            json_array_add_element(array, elem);
        }

        return json_node_init_array(json_node_new(JSON_NODE_ARRAY), array);
    }

//     printf("%s\n", json_to_string(make_json(root), 0));
    printf("%s\n", json_to_string(make_json(root), 1));

	return 0;
}


