// -------------------------------------------------------
// GitifierAppDelegate.m
//
// Copyright (c) 2010 Jakub Suder <jakub.suder@gmail.com>
// Licensed under Eclipse Public License v1.0
// -------------------------------------------------------

#import "Commit.h"
#import "Defaults.h"
#import "Git.h"
#import "GitifierAppDelegate.h"
#import "GrowlController.h"
#import "PreferencesWindowController.h"
#import "Repository.h"
#import "RepositoryListController.h"
#import "StatusBarController.h"
#import "GravatarController.h"

static NSString *SUEnableAutomaticChecksKey = @"SUEnableAutomaticChecks";
static NSString *SUSendProfileInfoKey       = @"SUSendProfileInfo";
static CGFloat IntervalBetweenGrowls        = 0.05;
static NSRegularExpression *gitVersionRegex;

@interface GitifierAppDelegate ()

@property (strong) NSString *userEmail;
@property (strong) NSMutableArray *repositoryList;

@end

@implementation GitifierAppDelegate

// --- initialization and termination ---

+ (void) initialize {
  gitVersionRegex = [NSRegularExpression regularExpressionWithPattern: @"^git version \\d" options: 0 error: nil];
}

- (void) applicationDidFinishLaunching: (NSNotification *) aNotification {
  self.repositoryList = [NSMutableArray array];
  [Defaults registerDefaults];

  PSObserve(nil, NSWindowDidBecomeMainNotification, windowBecameMain:);
  PSObserve(nil, GitExecutableSetNotification, gitPathUpdated);
  ObserveDefaults(KeepWindowsOnTopKey);
  [self loadGitPath];

  [[GrowlController sharedController] setRepositoryListController: self.repositoryListController];

  [self askAboutStats];

  NSNotificationCenter *center = [[NSWorkspace sharedWorkspace] notificationCenter];
  [center addObserver: self
             selector: @selector(wakeupEvent:)
                 name: NSWorkspaceDidWakeNotification
               object: nil];
  [center addObserver: self
             selector: @selector(wakeupEvent:)
                 name: NSWorkspaceSessionDidBecomeActiveNotification
               object: nil];

  [self.repositoryListController loadRepositories];
  [self.statusBarController createStatusBarItem];
  [self.monitor startMonitoring];
  [self.monitor executeFetch];

  // preload preferences window to make it open faster
  self.preferencesWindowController = [[PreferencesWindowController alloc] init];
  [self.preferencesWindowController window];

  if ([[self.repositoryListController repositoryList] count] == 0) {
    [self showPreferences: self];
  }
}

- (void) askAboutStats {
  if ([GitifierDefaults boolForKey: SUEnableAutomaticChecksKey]
      && ![GitifierDefaults boolForKey: AskedAboutProfileInfoKey]) {
    NSInteger output = NSRunAlertPanel(
      @"Is it OK if Gitifier sends anonymous system stats (CPU, OS version etc.) with update requests?",
      @"This doesn't include any personal data, just some numbers. You won't be asked about this again.",
      @"Yeah, whatever",
      @"Please don't",
      nil
    );
    if (output == NSAlertDefaultReturn) {
      [GitifierDefaults setBool: YES forKey: SUSendProfileInfoKey];
    }
  }

  [GitifierDefaults setBool: YES forKey: AskedAboutProfileInfoKey];
}

- (void) wakeupEvent: (NSNotification *) notification {
  // on a new day, notify the user about repositories that are still failing
  // also, give the network some time to reconnect after the wakeup
  [self.repositoryListController performSelector: @selector(resetRepositoryStatuses) withObject: nil afterDelay: 10.0];
}

- (void) windowBecameMain: (NSNotification *) notification {
  NSWindow *window = [notification object];
  window.keepOnTop = [GitifierDefaults boolForKey: KeepWindowsOnTopKey];
}

- (void) observeValueForKeyPath: (NSString *) keyPath
                       ofObject: (id) object
                         change: (NSDictionary *) change
                        context: (void *) context {
  if ([[keyPath lastKeyPathElement] isEqual: KeepWindowsOnTopKey]) {
    BOOL keepOnTop = [GitifierDefaults boolForKey: KeepWindowsOnTopKey];
    NSArray *windows = [NSApp windows];
    NSWindow *mainWindow = nil;

    for (NSWindow *window in windows) {
      if ([window isMainWindow]) {
        mainWindow = window;
      } else {
        window.keepOnTop = keepOnTop;
      }
    }

    mainWindow.keepOnTop = keepOnTop;
  }
}

// --- actions ---

- (IBAction) showPreferences: (id) sender {
  [NSApp activateIgnoringOtherApps: YES];
  [self.preferencesWindowController showWindow: self];
}

- (IBAction) checkNow: (id) sender {
  [self.monitor restartMonitoring];
  [self.monitor executeFetch];
}

- (IBAction) quit: (id) sender {
  // if quit fails because of an open sheet, move the window to front
  [NSApp performSelector: @selector(activateIgnoringOtherApps:) withObject: @YES afterDelay: 0.1];
  [NSApp terminate: self];
}

// --- user email management ---

- (void) updateUserEmail {
  if (!self.userEmail && [Git gitExecutable]) {
    Git *git = [[Git alloc] initWithDelegate: self];
    [git runCommand: @"config" withArguments: @[@"user.email"] inPath: NSHomeDirectory()];
  }
}

// --- git path management ---

- (void) loadGitPath {
  NSString *path = [GitifierDefaults objectForKey: GitExecutableKey];
  if (path) {
    [Git setGitExecutable: path];
  } else {
    [self findGitPath];
  }
}

- (void) gitPathUpdated {
  NSString *git = [Git gitExecutable];
  if (git) {
    [self updateUserEmail];
    [self validateGitPath];
    [GitifierDefaults setObject: git forKey: GitExecutableKey];
  } else {
    [GitifierDefaults removeObjectForKey: GitExecutableKey];
  }
}

- (void) validateGitPath {
  Git *git = [[Git alloc] initWithDelegate: self];
  [git runCommand: @"version" inPath: NSHomeDirectory()];
}

- (void) findGitPath {
  NSPipe *inputPipe = [NSPipe pipe];
  NSPipe *outputPipe = [NSPipe pipe];
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[@"--login", @"-c", @"which git"];
  task.currentDirectoryPath = NSHomeDirectory();
  task.standardOutput = outputPipe;
  task.standardError = outputPipe;
  task.standardInput = inputPipe;
  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *e) {
    NSRunAlertPanel(@"Error: bash not found.",
                    @"Dude, if you don't even have bash, something is seriously wrong...",
                    @"OMG!", nil, nil);
    return;
  }

  NSData *data = [[[task standardOutput] fileHandleForReading] readDataToEndOfFile];
  NSString *output = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] psTrimmedString];

  if (output && (output.length > 0) && (task.terminationStatus == 0)) {
    [Git setGitExecutable: output];
  }
}

- (void) rejectGitPath {
  NSRunAlertPanel(@"Incorrect Git path",
                  PSFormat(@"The file at %@ is not a Git executable.", [Git gitExecutable]),
                  @"OK", nil, nil);
  [Git setGitExecutable: nil];
}

// --- git command callbacks ---

- (void) commandCompleted: (NSString *) command output: (NSString *) output {
  if ([command isEqual: @"config"]) {
    if (output && output.length > 0) {
      self.userEmail = [output psTrimmedString];
      PSNotifyWithData(UserEmailChangedNotification, @{@"email": self.userEmail});
    }
  } else if ([command isEqual: @"version"]) {
    if (!output || ![output isMatchedByRegex: gitVersionRegex]) {
      [self rejectGitPath];
    }
  }
}

- (void) commandFailed: (NSString *) command output: (NSString *) output {
  if ([command isEqual: @"version"]) {
    [self rejectGitPath];
  }
}

// --- repository callbacks ---

- (void) commitsReceived: (NSArray *) commits inRepository: (Repository *) repository {
  BOOL areGravatarIconsEnabled = [GitifierDefaults boolForKey: GravatarIconsEnabledKey];
  BOOL hasNotificationLimit = [GitifierDefaults boolForKey: NotificationLimitEnabledKey];
  NSInteger notificationLimit = [GitifierDefaults integerForKey: NotificationLimitValueKey];
    
  if(areGravatarIconsEnabled || YES){
    //if there are any commits without gravatar data, try to load them first before continuing
    NSMutableSet *authorsWithoutGravatar = [NSMutableSet set];

    @synchronized(authorsWithoutGravatar) {
      for (Commit *commit in commits) {
        if( commit.authorEmail.length>0 && commit.authorGravatar==nil && ![authorsWithoutGravatar containsObject:commit.authorEmail]){
          
          NSData *imageData = [[GravatarController sharedController] imageDataForEmailAddress:commit.authorEmail completionHandler:^(NSString *emailAddress, NSData *imageData, NSError *connectionError) {
            BOOL isGravatarFinished;
            
            @synchronized (authorsWithoutGravatar){
              [authorsWithoutGravatar removeObject:emailAddress];
              isGravatarFinished = authorsWithoutGravatar.count == 0;
              commit.authorGravatar=imageData;
            }
            
            if(isGravatarFinished)
              [self commitsReceived:commits inRepository:repository];
          }];
          
          if(imageData)
            commit.authorGravatar = imageData;
          else
            [authorsWithoutGravatar addObject:commit.authorEmail];
        }
      }
      
      if(authorsWithoutGravatar.count > 0)
        return; //this function will be called again after all gravatars have been loaded
    }
  }
  
  NSArray *relevantCommits = [Commit chooseRelevantCommits: commits forUser: self.userEmail];
  NSArray *displayedCommits, *remainingCommits;

  if (hasNotificationLimit && relevantCommits.count > notificationLimit) {
    NSInteger displayed = notificationLimit - 1;
    displayedCommits = [relevantCommits subarrayWithRange: NSMakeRange(0, displayed)];
    remainingCommits = [relevantCommits subarrayWithRange: NSMakeRange(displayed, relevantCommits.count - displayed)];
  } else {
    displayedCommits = relevantCommits;
    remainingCommits = @[];
  }

  GrowlController *growl = [GrowlController sharedController];
  NSInteger i = 0;

  for (Commit *commit in displayedCommits) {
    // intervals added because Growl 1.3 can't figure out the proper order by itself...
    [growl performSelector: @selector(showGrowlWithCommit:) withObject: commit afterDelay: i * IntervalBetweenGrowls];
    i += 1;
  }

  if (remainingCommits.count > 0) {
    SEL action;

    if (notificationLimit == 1) {
      action = @selector(showGrowlWithCommitGroupIncludingAllCommits:);
    } else {
      action = @selector(showGrowlWithCommitGroupIncludingSomeCommits:);
    }

    [growl performSelector: action withObject: remainingCommits afterDelay: i * IntervalBetweenGrowls];
  }

  [self.statusBarController updateRecentCommitsList: relevantCommits];
}

// these should be rare, only when a fetch fails and a repository needs to be recloned

- (void) repositoryWasCloned: (Repository *) repository {
  [repository fetchNewCommits];
}

- (void) repositoryCouldNotBeCloned: (Repository *) repository {
  [[GrowlController sharedController] showGrowlWithError: @"Cached copy was deleted and can't be restored."
                                              repository: repository];
}

@end
