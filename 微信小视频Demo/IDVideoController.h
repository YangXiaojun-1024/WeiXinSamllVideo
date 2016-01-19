//
//  IDVideoController.h
//  iPatient
//
//  Created by apple on 15/11/25.
//  Copyright © 2015年 someone. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol IDVideoControllerDelegate <NSObject>

@required
- (void)IDVideoControllerDidFinishedTakeMovie:(NSURL *)mp4URL;

@end

@interface IDVideoController : UIViewController

@property(nonatomic, weak) id<IDVideoControllerDelegate>delegate;

@end
