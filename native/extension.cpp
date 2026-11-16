#include "mobile.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <cstring>
using namespace godot;

class NetHackSession : public RefCounted {
    GDCLASS(NetHackSession, RefCounted);
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("start", "directory", "name"), &NetHackSession::start);
        ClassDB::bind_method(D_METHOD("poll"), &NetHackSession::poll);
        ClassDB::bind_method(D_METHOD("respond", "input"), &NetHackSession::respond);
        ClassDB::bind_method(D_METHOD("suspend"), &NetHackSession::suspend);
        ClassDB::bind_method(D_METHOD("stop"), &NetHackSession::stop);
        ClassDB::bind_method(D_METHOD("is_running"), &NetHackSession::is_running);
    }
public:
    bool start(const String &directory, const String &name) { return nm_start(directory.utf8().get_data(), name.utf8().get_data()) != 0; }
    Array poll() {
        Array result; nm_event event;
        for (int count = 0; count < 4096 && nm_poll(&event); ++count) {
            Dictionary e;
            e["type"] = event.type; e["request"] = (int64_t)event.request;
            PackedInt64Array values; for (auto v : event.values) values.push_back(v);
            e["v"] = values; e["text"] = String::utf8(event.text);
            size_t offset = std::strlen(event.text) + 1;
            e["extra"] = offset < sizeof event.text ? String::utf8(event.text + offset) : String();
            result.push_back(e);
        }
        return result;
    }
    bool respond(const Dictionary &d) {
        nm_input input{};
        input.request = (int64_t)d.get("request", 0);
        input.type = d.get("type", NM_KEY); input.key = d.get("key", 0);
        input.x = d.get("x", 0); input.y = d.get("y", 0); input.mod = d.get("mod", 0);
        String text = d.get("text", ""); auto bytes = text.utf8();
        std::snprintf(input.text, sizeof input.text, "%s", bytes.get_data());
        return nm_respond(&input) != 0;
    }
    void suspend() { nm_suspend(); }
    void stop() { nm_stop(); }
    bool is_running() { return nm_running() != 0; }
    ~NetHackSession() { nm_stop(); }
};

static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<NetHackSession>();
}
static void uninitialize(ModuleInitializationLevel level) {}
extern "C" GDExtensionBool GDE_EXPORT nethack_mobile_init(GDExtensionInterfaceGetProcAddress get_proc_address,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize); init.register_terminator(uninitialize);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
