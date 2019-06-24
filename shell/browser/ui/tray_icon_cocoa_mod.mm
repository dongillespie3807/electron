// Copyright (c) 2014 GitHub, Inc.
// Use of this source code is governed by the MIT license that can be
// found in the LICENSE file.

#include "atom/browser/ui/tray_icon_cocoa.h"

#include <string>
#include <vector>

#include "atom/browser/mac/atom_application.h"
#include "atom/browser/ui/cocoa/NSString+ANSI.h"
#include "atom/browser/ui/cocoa/atom_menu_controller.h"
#include "base/mac/sdk_forward_declarations.h"
#include "base/strings/sys_string_conversions.h"
#include "ui/display/screen.h"
#include "ui/events/cocoa/cocoa_event_utils.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/mac/coordinate_conversion.h"

@interface StatusItemView : NSView {
  atom::TrayIconCocoa* trayIcon_;       // weak
  AtomMenuController* menuController_;  // weak
  atom::TrayIcon::HighlightMode highlight_mode_;
  BOOL ignoreDoubleClickEvents_;
  BOOL forceHighlight_;
  BOOL inMouseEventSequence_;
  base::scoped_nsobject<NSStatusItem> statusItem_;
  base::scoped_nsobject<NSTrackingArea> trackingArea_;
}

@end  // @interface StatusItemView

@implementation StatusItemView

- (void)dealloc {
  trayIcon_ = nil;
  menuController_ = nil;
  [super dealloc];
}

- (id)initWithIcon:(atom::TrayIconCocoa*)icon {
  trayIcon_ = icon;
  menuController_ = nil;
  highlight_mode_ = atom::TrayIcon::HighlightMode::SELECTION;
  ignoreDoubleClickEvents_ = NO;
  forceHighlight_ = NO;
  inMouseEventSequence_ = NO;

  if ((self = [super initWithFrame:CGRectZero])) {
    [self registerForDraggedTypes:@[
      NSFilenamesPboardType,
      NSStringPboardType,
    ]];

    // Create the status item.
    NSStatusItem* item = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    statusItem_.reset([item retain]);
    // Finalize setup by sizing our views
    [self updateDimensions];

    // Add NSTrackingArea for listening to mouseEnter, mouseExit, and mouseMove
    // events
    trackingArea_.reset([[NSTrackingArea alloc]
        initWithRect:[self bounds]
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                     NSTrackingActiveAlways
               owner:self
            userInfo:nil]);
    [[statusItem_ button] addTrackingArea:trackingArea_];
  }
  return self;
}

- (void)updateDimensions {
  NSRect rect = [statusItem_ button].frame;
  [self setFrame:NSMakeRect(0, 0, rect.size.width, rect.size.height)];
  // [self setNeedsDisplay:YES];
}

- (void)removeItem {
  // Turn off tracking events to prevent crash
  if (trackingArea_) {
    [self removeTrackingArea:trackingArea_];
    trackingArea_.reset();
  }
  [[NSStatusBar systemStatusBar] removeStatusItem:statusItem_];
  statusItem_.reset();
}

- (BOOL)isDarkMode {
  if (@available(macOS 10.14, *)) {
    return [[NSApplication sharedApplication].effectiveAppearance.name
        isEqualToString:NSAppearanceNameDarkAqua];
  }
  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
  NSString* mode = [defaults stringForKey:@"AppleInterfaceStyle"];
  return mode && [mode isEqualToString:@"Dark"];
}

- (BOOL)isHighlighted {
  BOOL highlight = [self shouldHighlight];
  return highlight | [self isDarkMode];
}

- (void)setImage:(NSImage*)image {
  [[statusItem_ button] setImage:image];  // TODO: or [image copy] ?
  [self updateDimensions];
}

- (void)setAlternateImage:(NSImage*)image {
  [[statusItem_ button] setAlternateImage:image];  // TODO: or [image copy] ?
}

- (void)setHighlight:(atom::TrayIcon::HighlightMode)mode {
  highlight_mode_ = mode;
  // [self setNeedsDisplay:YES];
}

- (void)setIgnoreDoubleClickEvents:(BOOL)ignore {
  ignoreDoubleClickEvents_ = ignore;
}

- (BOOL)getIgnoreDoubleClickEvents {
  return ignoreDoubleClickEvents_;
}

- (void)setTitle:(NSString*)title {
  [[statusItem_ button] setTitle:title];  // TODO: or [title copy] ?

  // Fix icon margins.
  if (title.length == 0) {
    [[statusItem_ button] setImagePosition:NSImageOnly];
  } else {
    [[statusItem_ button] setImagePosition:NSImageLeft];
  }

  [self updateDimensions];
}

- (NSString*)title {
  return [statusItem_ button].title;
}

- (void)setMenuController:(AtomMenuController*)menu {
  menuController_ = menu;
}

- (void)mouseDown:(NSEvent*)event {
  inMouseEventSequence_ = YES;
  // [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent*)event {
  if (!inMouseEventSequence_) {
    // If the menu is showing, when user clicked the tray icon, the `mouseDown`
    // event will be dissmissed, we need to close the menu at this time.
    // [self setNeedsDisplay:YES];
    return;
  }
  inMouseEventSequence_ = NO;

  // Show menu when there is a context menu.
  // NB(hokein): Make tray's behavior more like official one's.
  // When the tray icon gets clicked quickly multiple times, the
  // event.clickCount doesn't always return 1. Instead, it returns a value that
  // counts the clicked times.
  // So we don't check the clickCount here, just pop up the menu for each click
  // event.
  if (menuController_)
    [statusItem_ setMenu:[menuController_ menu]];

  // Don't emit click events when menu is showing.
  if (menuController_)
    return;

  // If we are ignoring double click events, we should ignore the `clickCount`
  // value and immediately emit a click event.
  BOOL shouldBeHandledAsASingleClick =
      (event.clickCount == 1) || ignoreDoubleClickEvents_;
  if (shouldBeHandledAsASingleClick)
    trayIcon_->NotifyClicked(
        gfx::ScreenRectFromNSRect(event.window.frame),
        gfx::ScreenPointFromNSPoint([event locationInWindow]),
        ui::EventFlagsFromModifiers([event modifierFlags]));

  // Double click event.
  BOOL shouldBeHandledAsADoubleClick =
      (event.clickCount == 2) && !ignoreDoubleClickEvents_;
  if (shouldBeHandledAsADoubleClick)
    trayIcon_->NotifyDoubleClicked(
        gfx::ScreenRectFromNSRect(event.window.frame),
        ui::EventFlagsFromModifiers([event modifierFlags]));

  // [self setNeedsDisplay:YES];
}

- (void)popUpContextMenu:(atom::AtomMenuModel*)menu_model {
  // Show a custom menu.
  if (menu_model) {
    base::scoped_nsobject<AtomMenuController> menuController(
        [[AtomMenuController alloc] initWithModel:menu_model
                            useDefaultAccelerator:NO]);
    forceHighlight_ = YES;  // Should highlight when showing menu.
    // [self setNeedsDisplay:YES];
    [statusItem_ popUpStatusItemMenu:[menuController menu]];
    forceHighlight_ = NO;
    // [self setNeedsDisplay:YES];
    return;
  }

  if (menuController_ && ![menuController_ isMenuOpen]) {
    // Redraw the tray icon to show highlight if it is enabled.
    // [self setNeedsDisplay:YES];
    [statusItem_ popUpStatusItemMenu:[menuController_ menu]];
    // The popUpStatusItemMenu returns only after the showing menu is closed.
    // When it returns, we need to redraw the tray icon to not show highlight.
    // [self setNeedsDisplay:YES];
  }
}

- (void)rightMouseUp:(NSEvent*)event {
  trayIcon_->NotifyRightClicked(
      gfx::ScreenRectFromNSRect(event.window.frame),
      ui::EventFlagsFromModifiers([event modifierFlags]));
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
  trayIcon_->NotifyDragEntered();
  return NSDragOperationCopy;
}

- (void)mouseExited:(NSEvent*)event {
  trayIcon_->NotifyMouseExited(
      gfx::ScreenPointFromNSPoint([event locationInWindow]),
      ui::EventFlagsFromModifiers([event modifierFlags]));
}

- (void)mouseEntered:(NSEvent*)event {
  trayIcon_->NotifyMouseEntered(
      gfx::ScreenPointFromNSPoint([event locationInWindow]),
      ui::EventFlagsFromModifiers([event modifierFlags]));
}

- (void)mouseMoved:(NSEvent*)event {
  trayIcon_->NotifyMouseMoved(
      gfx::ScreenPointFromNSPoint([event locationInWindow]),
      ui::EventFlagsFromModifiers([event modifierFlags]));
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
  trayIcon_->NotifyDragExited();
}

- (void)draggingEnded:(id<NSDraggingInfo>)sender {
  trayIcon_->NotifyDragEnded();

  if (NSPointInRect([sender draggingLocation], self.frame)) {
    trayIcon_->NotifyDrop();
  }
}

- (BOOL)handleDrop:(id<NSDraggingInfo>)sender {
  NSPasteboard* pboard = [sender draggingPasteboard];

  if ([[pboard types] containsObject:NSFilenamesPboardType]) {
    std::vector<std::string> dropFiles;
    NSArray* files = [pboard propertyListForType:NSFilenamesPboardType];
    for (NSString* file in files)
      dropFiles.push_back(base::SysNSStringToUTF8(file));
    trayIcon_->NotifyDropFiles(dropFiles);
    return YES;
  } else if ([[pboard types] containsObject:NSStringPboardType]) {
    NSString* dropText = [pboard stringForType:NSStringPboardType];
    trayIcon_->NotifyDropText(base::SysNSStringToUTF8(dropText));
    return YES;
  }

  return NO;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
  return YES;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
  [self handleDrop:sender];
  return YES;
}

- (BOOL)shouldHighlight {
  using HighlightMode = atom::TrayIcon::HighlightMode;
  switch (highlight_mode_) {
    case HighlightMode::ALWAYS:
      return true;
    case HighlightMode::NEVER:
      return false;
    case HighlightMode::SELECTION:
      BOOL isMenuOpen = menuController_ && [menuController_ isMenuOpen];
      return forceHighlight_ || inMouseEventSequence_ || isMenuOpen;
  }
}

@end

namespace atom {

TrayIconCocoa::TrayIconCocoa() {
  status_item_view_.reset([[StatusItemView alloc] initWithIcon:this]);
}

TrayIconCocoa::~TrayIconCocoa() {
  [status_item_view_ removeItem];
  if (menu_model_)
    menu_model_->RemoveObserver(this);
}

void TrayIconCocoa::SetImage(const gfx::Image& image) {
  [status_item_view_ setImage:image.IsEmpty() ? nil : image.AsNSImage()];
}

void TrayIconCocoa::SetPressedImage(const gfx::Image& image) {
  [status_item_view_ setAlternateImage:image.AsNSImage()];
}

void TrayIconCocoa::SetToolTip(const std::string& tool_tip) {
  [status_item_view_ setToolTip:base::SysUTF8ToNSString(tool_tip)];
}

void TrayIconCocoa::SetTitle(const std::string& title) {
  [status_item_view_ setTitle:base::SysUTF8ToNSString(title)];
}

std::string TrayIconCocoa::GetTitle() {
  return base::SysNSStringToUTF8([status_item_view_ title]);
}

void TrayIconCocoa::SetHighlightMode(TrayIcon::HighlightMode mode) {
  [status_item_view_ setHighlight:mode];
}

void TrayIconCocoa::SetIgnoreDoubleClickEvents(bool ignore) {
  [status_item_view_ setIgnoreDoubleClickEvents:ignore];
}

bool TrayIconCocoa::GetIgnoreDoubleClickEvents() {
  return [status_item_view_ getIgnoreDoubleClickEvents];
}

void TrayIconCocoa::PopUpContextMenu(const gfx::Point& pos,
                                     AtomMenuModel* menu_model) {
  [status_item_view_ popUpContextMenu:menu_model];
}

void TrayIconCocoa::SetContextMenu(AtomMenuModel* menu_model) {
  // Substribe to MenuClosed event.
  if (menu_model_)
    menu_model_->RemoveObserver(this);

  menu_model_ = menu_model;

  if (menu_model) {
    menu_model->AddObserver(this);
    // Create native menu.
    menu_.reset([[AtomMenuController alloc] initWithModel:menu_model
                                    useDefaultAccelerator:NO]);
  } else {
    menu_.reset();
  }

  [status_item_view_ setMenuController:menu_.get()];
}

gfx::Rect TrayIconCocoa::GetBounds() {
  auto bounds = gfx::ScreenRectFromNSRect([status_item_view_ window].frame);
  return bounds;
}

void TrayIconCocoa::OnMenuWillClose() {
  // [status_item_view_ setNeedsDisplay:YES];
}

// static
TrayIcon* TrayIcon::Create() {
  return new TrayIconCocoa;
}

}  // namespace atom
