#include "space.h"
#include "display.h"
#include "window.h"
#include "tree.h"
#include "border.h"
#include "keys.h"
#include "helpers.h"
#include "../axlib/axlib.h"

extern std::map<std::string, space_info> WindowTree;
extern ax_application *FocusedApplication;
extern kwm_settings KWMSettings;

void GetTagForMonocleSpace(space_info *Space, std::string &Tag)
{
    tree_node *Node = Space->RootNode;
    bool FoundFocusedWindow = false;
    int FocusedIndex = 0;
    int NumberOfWindows = 0;

    if(Node)
    {
        if(FocusedApplication)
        {
            ax_window *Window = FocusedApplication->Focus;
            if(Window)
            {
                link_node *Link = Node->List;
                while(Link)
                {
                    if(!FoundFocusedWindow)
                        ++FocusedIndex;

                    if(Link->WindowID == Window->ID)
                        FoundFocusedWindow = true;

                    ++NumberOfWindows;
                    Link = Link->Next;
                }
            }
        }
    }

    if(FoundFocusedWindow)
        Tag = "[" + std::to_string(FocusedIndex) + "/" + std::to_string(NumberOfWindows) + "]";
    else
        Tag = "[" + std::to_string(NumberOfWindows) + "]";
}

void GetTagForCurrentSpace(std::string &Tag, ax_window *Window)
{
    ax_display *Display = Window ? AXLibWindowDisplay(Window) : AXLibMainDisplay();
    space_info *SpaceInfo = &WindowTree[Display->Space->Identifier];

    if(SpaceInfo->Initialized)
    {
        if(SpaceInfo->Settings.Mode == SpaceModeBSP)
            Tag = "[bsp]";
        else if(SpaceInfo->Settings.Mode == SpaceModeFloating)
            Tag = "[float]";
        else if(SpaceInfo->Settings.Mode == SpaceModeMonocle)
            GetTagForMonocleSpace(SpaceInfo, Tag);
    }
    else
    {
        if(KWMSettings.Space == SpaceModeBSP)
            Tag = "[bsp]";
        else if(KWMSettings.Space == SpaceModeFloating)
            Tag = "[float]";
        else if(KWMSettings.Space == SpaceModeMonocle)
            Tag = "[monocle]";
    }
}

void GoToPreviousSpace(bool MoveFocusedWindow)
{
    if(AXLibIsSpaceTransitionInProgress())
        return;

    ax_display *Display = AXLibMainDisplay();
    if(Display && Display->PrevSpace)
    {
        int Workspace = AXLibDesktopIDFromCGSSpaceID(Display, Display->PrevSpace->ID);
        std::string WorkspaceStr = std::to_string(Workspace);

        if(MoveFocusedWindow)
            MoveFocusedWindowToSpace(WorkspaceStr);
        else
            ActivateSpaceWithoutTransition(WorkspaceStr);
    }
}

space_settings *GetSpaceSettingsForDesktopID(int ScreenID, int DesktopID)
{
    space_identifier Lookup = { ScreenID, DesktopID };
    std::map<space_identifier, space_settings>::iterator It = KWMSettings.SpaceSettings.find(Lookup);
    if(It != KWMSettings.SpaceSettings.end())
        return &It->second;
    else
        return NULL;
}

void LoadSpaceSettings(ax_display *Display, space_info *SpaceInfo)
{
    int DesktopID = AXLibDesktopIDFromCGSSpaceID(Display, Display->Space->ID);

    /* NOTE(koekeishiya): Load global default display settings. */
    SpaceInfo->Settings.Offset = KWMSettings.DefaultOffset;
    SpaceInfo->Settings.Mode = SpaceModeDefault;
    SpaceInfo->Settings.Layout = "";
    SpaceInfo->Settings.Name = "";

    /* NOTE(koekeishiya): The space in question may have overloaded settings. */
    space_settings *SpaceSettings = NULL;
    if((SpaceSettings = GetSpaceSettingsForDesktopID(Display->ArrangementID, DesktopID)))
        SpaceInfo->Settings = *SpaceSettings;
    else if((SpaceSettings = GetSpaceSettingsForDisplay(Display->ArrangementID)))
        SpaceInfo->Settings = *SpaceSettings;

    if(SpaceInfo->Settings.Mode == SpaceModeDefault)
        SpaceInfo->Settings.Mode = KWMSettings.Space;
}

int GetSpaceFromName(ax_display *Display, std::string Name)
{
    std::map<CGSSpaceID, ax_space>::iterator It;
    for(It = Display->Spaces.begin(); It != Display->Spaces.end(); ++It)
    {
        ax_space *Space = &It->second;
        space_info *SpaceInfo = &WindowTree[Space->Identifier];
        if(SpaceInfo->Settings.Name == Name)
            return Space->ID;
    }

    return -1;
}

void SetNameOfActiveSpace(ax_display *Display, std::string Name)
{
    space_info *SpaceInfo = &WindowTree[Display->Space->Identifier];
    if(SpaceInfo) SpaceInfo->Settings.Name = Name;
}

std::string GetNameOfSpace(ax_display *Display, ax_space *Space)
{
    space_info *SpaceInfo = &WindowTree[Space->Identifier];
    std::string Result = "[no tag]";

    if(!SpaceInfo->Settings.Name.empty())
        Result = SpaceInfo->Settings.Name;

    return Result;
}

void ActivateSpaceWithoutTransition(std::string SpaceID)
{
    ax_display *Display = AXLibMainDisplay();
    if(Display)
    {
        int TotalSpaces = AXLibDisplaySpacesCount(Display);
        int ActiveSpace = AXLibDesktopIDFromCGSSpaceID(Display, Display->Space->ID);
        int DestinationSpaceID = ActiveSpace;
        if(SpaceID == "left")
        {
            DestinationSpaceID = ActiveSpace > 1 ? ActiveSpace-1 : 1;
        }
        else if(SpaceID == "right")
        {
            DestinationSpaceID = ActiveSpace < TotalSpaces ? ActiveSpace+1 : TotalSpaces;
        }
        else
        {
            int LookupSpace = GetSpaceFromName(Display, SpaceID);
            if(LookupSpace != -1)
                DestinationSpaceID = AXLibDesktopIDFromCGSSpaceID(Display, LookupSpace);
            else
                DestinationSpaceID = std::atoi(SpaceID.c_str());
        }

        if(DestinationSpaceID != ActiveSpace &&
           DestinationSpaceID > 0 && DestinationSpaceID <= TotalSpaces)
        {
            int CGSSpaceID = AXLibCGSSpaceIDFromDesktopID(Display, DestinationSpaceID);
            ax_space *Space = &Display->Spaces[CGSSpaceID];
            AXLibAddFlags(Space, AXSpace_FastTransition);
            AXLibSpaceTransition(Display, CGSSpaceID);
        }
    }
}

void MoveWindowBetweenSpaces(ax_display *Display, int SourceSpaceID, int DestinationSpaceID, ax_window *Window)
{
    int SourceCGSpaceID = AXLibCGSSpaceIDFromDesktopID(Display, SourceSpaceID);
    int DestinationCGSpaceID = AXLibCGSSpaceIDFromDesktopID(Display, DestinationSpaceID);
    RemoveWindowFromNodeTree(Display, Window->ID);
    AXLibSpaceRemoveWindow(SourceCGSpaceID, Window->ID);
    AXLibSpaceAddWindow(DestinationCGSpaceID, Window->ID);
}

void MoveFocusedWindowToSpace(std::string SpaceID)
{
    ax_window *Window = FocusedApplication->Focus;
    if(!Window)
        return;

    ax_display *Display = AXLibWindowDisplay(Window);
    int TotalSpaces = AXLibDisplaySpacesCount(Display);
    int ActiveSpace = AXLibDesktopIDFromCGSSpaceID(Display, Display->Space->ID);
    int DestinationSpaceID = ActiveSpace;
    if(SpaceID == "left")
    {
        DestinationSpaceID = ActiveSpace > 1 ? ActiveSpace-1 : 1;
    }
    else if(SpaceID == "right")
    {
        DestinationSpaceID = ActiveSpace < TotalSpaces ? ActiveSpace+1 : TotalSpaces;
    }
    else
    {
        int LookupSpace = GetSpaceFromName(Display, SpaceID);
        if(LookupSpace != -1)
            DestinationSpaceID = AXLibDesktopIDFromCGSSpaceID(Display, LookupSpace);
        else
            DestinationSpaceID = std::atoi(SpaceID.c_str());
    }

    MoveWindowBetweenSpaces(Display, ActiveSpace, DestinationSpaceID, Window);
}
