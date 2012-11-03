// -------------------------------------------------------
// GeneralPanelController.h
//
// Copyright (c) 2011 Jakub Suder <jakub.suder@gmail.com>
// Licensed under Eclipse Public License v1.0
// -------------------------------------------------------

#import "MASPreferencesViewController.h"

@interface GeneralPanelController : NSViewController <MASPreferencesViewController, NSOpenSavePanelDelegate>

@property IBOutlet NSTextField *monitorIntervalField;
@property IBOutlet NSButton *chooseGitPathButton;
@property (readonly) id gitClass;

- (IBAction) openGitExecutableDialog: (id) sender;

@end
