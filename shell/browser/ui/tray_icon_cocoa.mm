// Copyright (c) 2014 GitHub, Inc.
// Use of this source code is governed by the MIT license that can be
// found in the LICENSE file.

#include "shell/browser/ui/tray_icon_cocoa.h"

#include <string>
#include <vector>

#include "base/strings/sys_string_conversions.h"
#include "shell/browser/ui/cocoa/atom_menu_controller.h"
#include "ui/gfx/mac/coordinate_conversion.h"

namespace electron {

TrayIconCocoa::TrayIconCocoa() {
  LOG(INFO) << "TrayIconCocoa()";

  // Create status bar item.
  NSStatusItem* item = [[NSStatusBar systemStatusBar]
      statusItemWithLength:NSVariableStatusItemLength];
  status_item_.reset([item retain]);

  // Set event handlers.
  // [[item button] setTarget:self];
  // [[item button] setAction:@selector(myMethodToCallOnClick:)];
}

TrayIconCocoa::~TrayIconCocoa() {
  LOG(INFO) << "~TrayIconCocoa()";
}

void TrayIconCocoa::SetImage(const gfx::Image& image) {
  [[status_item_ button] setImage:image.IsEmpty() ? nil : image.AsNSImage()];
}

void TrayIconCocoa::SetPressedImage(const gfx::Image& image) {
  [[status_item_ button]
      setAlternateImage:image.IsEmpty() ? nil : image.AsNSImage()];
}

void TrayIconCocoa::SetToolTip(const std::string& tool_tip) {
  [[status_item_ button] setToolTip:base::SysUTF8ToNSString(tool_tip)];
}

void TrayIconCocoa::SetTitle(const std::string& title) {
  [[status_item_ button] setTitle:base::SysUTF8ToNSString(title)];

  // Fix icon margins.
  if (title.empty()) {
    [[status_item_ button] setImagePosition:NSImageOnly];
  } else {
    [[status_item_ button] setImagePosition:NSImageLeft];
  }
}

std::string TrayIconCocoa::GetTitle() {
  return base::SysNSStringToUTF8([[status_item_ button] title]);
}

void TrayIconCocoa::SetHighlightMode(TrayIcon::HighlightMode mode) {
  LOG(INFO) << "SetHighlightMode()";

  // [[status_item_ button] setHighlight:YES];
  // [[status_item_ button] setHighlightMode:mode];
}

void TrayIconCocoa::SetIgnoreDoubleClickEvents(bool ignore) {
  LOG(INFO) << "SetIgnoreDoubleClickEvents()";
}

bool TrayIconCocoa::GetIgnoreDoubleClickEvents() {
  LOG(INFO) << "GetIgnoreDoubleClickEvents()";
  return false;
}

void TrayIconCocoa::PopUpContextMenu(const gfx::Point& pos,
                                     AtomMenuModel* menu_model) {
  LOG(INFO) << "PopUpContextMenu()";
}

void TrayIconCocoa::SetContextMenu(AtomMenuModel* menu_model) {
  LOG(INFO) << "SetContextMenu()";

  if (menu_model) {
    base::scoped_nsobject<AtomMenuController> menuController(
        [[AtomMenuController alloc] initWithModel:menu_model
                            useDefaultAccelerator:NO]);
    [status_item_ setMenu:[menuController menu]];
  }
}

gfx::Rect TrayIconCocoa::GetBounds() {
  return gfx::ScreenRectFromNSRect([status_item_ button].frame);
}

// static
TrayIcon* TrayIcon::Create() {
  return new TrayIconCocoa;
}

}  // namespace atom
