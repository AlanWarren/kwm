#include "container.h"
#include "node.h"
#include "space.h"

#define internal static

extern std::map<std::string, space_info> WindowTree;
extern kwm_settings KWMSettings;

internal node_container
LeftVerticalContainerSplit(ax_display *Display, tree_node *Node)
{
    space_info *SpaceInfo = &WindowTree[Display->Space->Identifier];
    node_container LeftContainer;

    LeftContainer.X = Node->Container.X;
    LeftContainer.Y = Node->Container.Y;
    LeftContainer.Width = (Node->Container.Width * Node->SplitRatio) - (SpaceInfo->Settings.Offset.VerticalGap / 2);
    LeftContainer.Height = Node->Container.Height;

    return LeftContainer;
}

internal node_container
RightVerticalContainerSplit(ax_display *Display, tree_node *Node)
{
    space_info *SpaceInfo = &WindowTree[Display->Space->Identifier];
    node_container RightContainer;

    RightContainer.X = Node->Container.X + (Node->Container.Width * Node->SplitRatio) + (SpaceInfo->Settings.Offset.VerticalGap / 2);
    RightContainer.Y = Node->Container.Y;
    RightContainer.Width = (Node->Container.Width * (1 - Node->SplitRatio)) - (SpaceInfo->Settings.Offset.VerticalGap / 2);
    RightContainer.Height = Node->Container.Height;

    return RightContainer;
}

internal node_container
UpperHorizontalContainerSplit(ax_display *Display, tree_node *Node)
{
    space_info *SpaceInfo = &WindowTree[Display->Space->Identifier];
    node_container UpperContainer;

    UpperContainer.X = Node->Container.X;
    UpperContainer.Y = Node->Container.Y;
    UpperContainer.Width = Node->Container.Width;
    UpperContainer.Height = (Node->Container.Height * Node->SplitRatio) - (SpaceInfo->Settings.Offset.HorizontalGap / 2);

    return UpperContainer;
}

internal node_container
LowerHorizontalContainerSplit(ax_display *Display, tree_node *Node)
{
    space_info *SpaceInfo = &WindowTree[Display->Space->Identifier];
    node_container LowerContainer;

    LowerContainer.X = Node->Container.X;
    LowerContainer.Y = Node->Container.Y + (Node->Container.Height * Node->SplitRatio) + (SpaceInfo->Settings.Offset.HorizontalGap / 2);
    LowerContainer.Width = Node->Container.Width;
    LowerContainer.Height = (Node->Container.Height * (1 - Node->SplitRatio)) - (SpaceInfo->Settings.Offset.HorizontalGap / 2);

    return LowerContainer;
}

void SetRootNodeContainer(ax_display *Display, tree_node *Node)
{
    space_info *SpaceInfo = &WindowTree[Display->Space->Identifier];

    Node->Container.X = Display->Frame.origin.x + SpaceInfo->Settings.Offset.PaddingLeft;
    Node->Container.Y = Display->Frame.origin.y + SpaceInfo->Settings.Offset.PaddingTop;
    Node->Container.Width = Display->Frame.size.width - SpaceInfo->Settings.Offset.PaddingLeft - SpaceInfo->Settings.Offset.PaddingRight;
    Node->Container.Height = Display->Frame.size.height - SpaceInfo->Settings.Offset.PaddingTop - SpaceInfo->Settings.Offset.PaddingBottom;
    Node->SplitMode = GetOptimalSplitMode(Node);

    Node->Container.Type = CONTAINER_NONE;
}

void SetLinkNodeContainer(ax_display *Display, link_node *Link)
{
    space_info *SpaceInfo = &WindowTree[Display->Space->Identifier];

    Link->Container.X = Display->Frame.origin.x + SpaceInfo->Settings.Offset.PaddingLeft;
    Link->Container.Y = Display->Frame.origin.y + SpaceInfo->Settings.Offset.PaddingTop;
    Link->Container.Width = Display->Frame.size.width - SpaceInfo->Settings.Offset.PaddingLeft - SpaceInfo->Settings.Offset.PaddingRight;
    Link->Container.Height = Display->Frame.size.height - SpaceInfo->Settings.Offset.PaddingTop - SpaceInfo->Settings.Offset.PaddingBottom;
}

void CreateNodeContainer(ax_display *Display, tree_node *Node, container_type Type)
{
    if(Node->SplitRatio == 0)
        Node->SplitRatio = KWMSettings.SplitRatio;

    switch(Type)
    {
        case CONTAINER_LEFT:
        {
            Node->Container = LeftVerticalContainerSplit(Display, Node->Parent);
        } break;
        case CONTAINER_RIGHT:
        {
            Node->Container = RightVerticalContainerSplit(Display, Node->Parent);
        } break;
        case CONTAINER_UPPER:
        {
            Node->Container = UpperHorizontalContainerSplit(Display, Node->Parent);
        } break;
        case CONTAINER_LOWER:
        {
            Node->Container = LowerHorizontalContainerSplit(Display, Node->Parent);
        } break;
        default: { /* NOTE(koekeishiya): No container specified. */} break;
    }

    if(Node->SplitMode == SPLIT_NONE)
        Node->SplitMode = GetOptimalSplitMode(Node);

    Node->Container.Type = Type;
}

void CreateNodeContainerPair(ax_display *Display, tree_node *LeftNode, tree_node *RightNode, split_type SplitMode)
{
    if(SplitMode == SPLIT_VERTICAL)
    {
        CreateNodeContainer(Display, LeftNode, CONTAINER_LEFT);
        CreateNodeContainer(Display, RightNode, CONTAINER_RIGHT);
    }
    else
    {
        CreateNodeContainer(Display, LeftNode, CONTAINER_UPPER);
        CreateNodeContainer(Display, RightNode, CONTAINER_LOWER);
    }
}

void ResizeNodeContainer(ax_display *Display, tree_node *Node)
{
    if(Node)
    {
        if(Node->LeftChild)
        {
            CreateNodeContainer(Display, Node->LeftChild, Node->LeftChild->Container.Type);
            ResizeNodeContainer(Display, Node->LeftChild);
            ResizeLinkNodeContainers(Node->LeftChild);
        }

        if(Node->RightChild)
        {
            CreateNodeContainer(Display, Node->RightChild, Node->RightChild->Container.Type);
            ResizeNodeContainer(Display, Node->RightChild);
            ResizeLinkNodeContainers(Node->RightChild);
        }
    }
}

void ResizeLinkNodeContainers(tree_node *Root)
{
    if(Root)
    {
        link_node *Link = Root->List;
        while(Link)
        {
            Link->Container = Root->Container;
            Link = Link->Next;
        }
    }
}

void CreateNodeContainers(ax_display *Display, tree_node *Node, bool OptimalSplit)
{
    if(Node && Node->LeftChild && Node->RightChild)
    {
        Node->SplitMode = OptimalSplit ? GetOptimalSplitMode(Node) : Node->SplitMode;
        CreateNodeContainerPair(Display, Node->LeftChild, Node->RightChild, Node->SplitMode);

        CreateNodeContainers(Display, Node->LeftChild, OptimalSplit);
        CreateNodeContainers(Display, Node->RightChild, OptimalSplit);
    }
}

void CreateDeserializedNodeContainer(ax_display *Display, tree_node *Node)
{
    int SplitMode = Node->Parent->SplitMode;
    container_type Type = CONTAINER_NONE;

    if(SplitMode == SPLIT_VERTICAL)
        Type = IsLeftChild(Node) ? CONTAINER_LEFT : CONTAINER_RIGHT;
    else
        Type = IsLeftChild(Node) ? CONTAINER_UPPER : CONTAINER_LOWER;

    CreateNodeContainer(Display, Node, Type);
}
