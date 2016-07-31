#ifndef TYPES_H
#define TYPES_H

#include <Carbon/Carbon.h>

#include <iostream>
#include <vector>
#include <queue>
#include <stack>
#include <map>
#include <fstream>
#include <sstream>
#include <string>
#include <chrono>

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libproc.h>
#include <signal.h>

#include <pthread.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>

#include "axlib/observer.h"

struct token;
struct tokenizer;
struct space_identifier;
struct color;
struct mode;
struct hotkey;
struct modifiers;
struct space_settings;
struct container_offset;

struct window_properties;
struct window_rule;
struct space_info;
struct node_container;
struct tree_node;
struct scratchpad;

struct kwm_mach;
struct kwm_border;
struct kwm_hotkeys;
struct kwm_path;
struct kwm_settings;
struct kwm_thread;

#ifdef DEBUG_BUILD
    #define DEBUG(x) std::cout << x << std::endl
    #define Assert(Expression) do \
                               { if(!(Expression)) \
                                   {\
                                       std::cout << "Assertion failed: " << #Expression << std::endl;\
                                       *(volatile int*)0 = 0;\
                                   } \
                               } while(0)
#else
    #define DEBUG(x) do {} while(0)
    #define Assert(Expression) do {} while(0)
#endif

typedef std::chrono::time_point<std::chrono::steady_clock> kwm_time_point;

enum focus_option
{
    FocusModeAutoraise,
    FocusModeStandby,
    FocusModeDisabled
};

enum cycle_focus_option
{
    CycleModeScreen,
    CycleModeDisabled
};

enum space_tiling_option
{
    SpaceModeBSP,
    SpaceModeMonocle,
    SpaceModeFloating,
    SpaceModeDefault
};

enum split_type
{
    SPLIT_OPTIMAL = -1,
    SPLIT_VERTICAL = 1,
    SPLIT_HORIZONTAL = 2
};

enum node_type
{
    NodeTypeTree,
    NodeTypeLink
};

enum hotkey_state
{
    HotkeyStateNone,
    HotkeyStateInclude,
    HotkeyStateExclude
};

enum token_type
{
    Token_Colon,
    Token_SemiColon,
    Token_Equals,
    Token_Dash,

    Token_OpenParen,
    Token_CloseParen,
    Token_OpenBracket,
    Token_CloseBracket,
    Token_OpenBrace,
    Token_CloseBrace,

    Token_Identifier,
    Token_String,
    Token_Digit,
    Token_Comment,
    Token_Hex,

    Token_EndOfStream,
    Token_Unknown,
};

struct token
{
    token_type Type;

    int TextLength;
    char *Text;
};

struct tokenizer
{
    char *At;
};

struct space_identifier
{

    int ScreenID, SpaceID;

    bool operator<(const space_identifier &Other) const
    {
        return (ScreenID < Other.ScreenID) ||
               (ScreenID == Other.ScreenID && SpaceID < Other.SpaceID);
    }
};

struct modifiers
{
    bool CmdKey;
    bool AltKey;
    bool CtrlKey;
    bool ShiftKey;
};

struct hotkey
{
    std::vector<std::string> List;
    hotkey_state State;
    bool Passthrough;

    modifiers Mod;
    CGKeyCode Key;

    std::string Mode;
    std::string Command;
};

struct container_offset
{
    double PaddingTop, PaddingBottom;
    double PaddingLeft, PaddingRight;
    double VerticalGap, HorizontalGap;
};

struct color
{
    double Red;
    double Green;
    double Blue;
    double Alpha;

    std::string Format;
};

struct mode
{
    std::vector<hotkey> Hotkeys;
    std::string Name;
    color Color;

    bool Prefix;
    double Timeout;
    std::string Restore;
    kwm_time_point Time;
};

struct node_container
{
    double X, Y;
    double Width, Height;
    int Type;
};

struct link_node
{
    uint32_t WindowID;
    node_container Container;

    link_node *Prev;
    link_node *Next;
};

struct tree_node
{
    uint32_t WindowID;
    node_type Type;
    node_container Container;

    link_node *List;

    tree_node *Parent;
    tree_node *LeftChild;
    tree_node *RightChild;

    split_type SplitMode;
    double SplitRatio;
};

struct window_properties
{
    int Display;
    int Space;
    int Float;
    int Scratchpad;
    std::string Role;
};

struct window_rule
{
    window_properties Properties;
    std::string Except;
    std::string Owner;
    std::string Name;
    std::string Role;
    std::string CustomRole;
};

struct ax_window;
struct scratchpad
{
    std::map<int, ax_window*> Windows;
    int LastFocus;
};

struct space_settings
{
    container_offset Offset;
    space_tiling_option Mode;
    std::string Layout;
    std::string Name;
};

struct space_info
{
    space_settings Settings;
    bool Initialized;
    bool NeedsUpdate;

    tree_node *RootNode;
};

struct kwm_mach
{
    CFRunLoopSourceRef RunLoopSource;
    CFMachPortRef EventTap;
    CGEventMask EventMask;
    bool DisableEventTapInternal;
};

struct kwm_border
{
    bool Enabled;
    FILE *Handle;

    double Radius;
    color Color;
    int Width;
};

struct kwm_hotkeys
{
    std::map<std::string, mode> Modes;
    mode *ActiveMode;
};

struct kwm_path
{
    std::string EnvHome;
    std::string FilePath;
    std::string ConfigFolder;
    std::string ConfigFile;
    std::string BSPLayouts;
};

struct kwm_settings
{
    space_tiling_option Space;
    cycle_focus_option Cycle;
    focus_option Focus;

    bool UseMouseFollowsFocus;
    bool UseBuiltinHotkeys;
    bool StandbyOnFloat;
    bool CenterOnFloat;

    double OptimalRatio;
    bool SpawnAsLeftChild;
    bool FloatNonResizable;
    bool LockToContainer;

    split_type SplitMode;
    double SplitRatio;
    container_offset DefaultOffset;

    std::map<unsigned int, space_settings> DisplaySettings;
    std::map<space_identifier, space_settings> SpaceSettings;
    std::vector<window_rule> WindowRules;
};

struct kwm_thread
{
    pthread_t SystemCommand;
    pthread_t Daemon;
};

#endif
