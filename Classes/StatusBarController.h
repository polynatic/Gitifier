// -------------------------------------------------------
// StatusBarController.h
//
// Copyright (c) 2010 Jakub Suder <jakub.suder@gmail.com>
// Licensed under Eclipse Public License v1.0
// -------------------------------------------------------

@interface StatusBarController : NSObject

@property (strong) IBOutlet NSMenu *statusBarMenu;

// public
- (void) createStatusBarItem;
- (void) updateRecentCommitsList: (NSArray *) newCommits;

// private
- (void) updateRecentCommitsSection;

@end
