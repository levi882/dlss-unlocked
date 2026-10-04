#pragma once
#include <cstring>
#include <string_view>
#include <unordered_map>
#include "menu_zh_dictionary.h"

// Translate only presentation. Original labels still reach ImHashStr/GetID,
// configuration, keyboard handling, and the rendering backends unchanged.
namespace MenuZh
{
inline bool Enabled = false;

inline const char* Lookup(std::string_view english)
{
    const auto& entries = Dictionary();
    const auto found = entries.find(english);
    return found == entries.end() ? nullptr : found->second;
}

inline const char* Text(const char* english)
{
    if (!Enabled || !english)
        return english;
    const auto translated = Lookup(english);
    return translated ? translated : english;
}

inline void Range(const char*& begin, const char*& end)
{
    if (!Enabled || !begin)
        return;
    const std::string_view original(begin, end ? size_t(end - begin) : std::strlen(begin));
    if (const auto translated = Lookup(original))
    {
        begin = translated;
        end = translated + std::strlen(translated);
    }
}
}
