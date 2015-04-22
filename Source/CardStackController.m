#import "CardStackController.h"
#import "CardView.h"
#import "POP.h"

static const CGFloat CardStackTitleBarBackgroundColorOffset = 1.0f / 16.0f;
static const CGFloat CardStackTopMargin = 10.0f;
static const CGFloat CardStackDepthOffset = 0.04f;
static const CGFloat CardStackOpenIfLargeThanPercent = 0.8f;
static const CGFloat CardStackVerticalVelocityLimitWhenMakingCardCurrent = 100.0f;

@interface CardStackController () <CardViewDelegate>

@property (nonatomic) BOOL isAnimating;
@property (nonatomic) BOOL isOpen;
@property (nonatomic) CGRect originalCardFrame;

@end

@implementation CardStackController

@synthesize titleBarBackgroundColor = _titleBarBackgroundColor;
@synthesize titleFont = _titleFont;

#pragma mark - Setters

- (void)setCards:(NSArray *)cards {
    _cards = cards;

    for (NSUInteger i = 0; i < cards.count; i++) {
        CardView *card = [cards objectAtIndex:i];
        card.tag = i;
    }
}

- (void)setViewControllers:(NSArray *)viewControllers {
    _viewControllers = [viewControllers copy];

    [self.cards makeObjectsPerformSelector:@selector(removeFromSuperview)];

    self.cards = [CardView cardsWithViewControllers:viewControllers];
    for (CardView *card in self.cards) {
        card.delegate = self;
        card.titleFont = self.titleFont;
        [self.view addSubview:card];
    }

    // make sure cards' title bar background colors have the depth effect
    [self updateCardTitleBarBackgroundColors];

    self.currentCardIndex = self.cards.count - 1;
}

- (void)setCurrentCardIndex:(NSUInteger)currentCardIndex {
    [self setCurrentCardIndex:currentCardIndex animated:NO];
}

- (void)setCurrentCardIndex:(NSUInteger)currentCardIndex animated:(BOOL)animated {
    _currentCardIndex = currentCardIndex;

    [self updateCardScales];
    [self updateCardLocationsAnimated:animated];

    // disable pan recognizer for cards above to current one to avoid unwanted panning
    for (NSUInteger i = 0; i < self.cards.count; i++) {
        CardView *card = [self.cards objectAtIndex:i];
        card.panRecognizer.enabled = (i >= currentCardIndex);
    }
}

- (void)setTitleBarBackgroundColor:(UIColor *)titleBarBackgroundColor {
    _titleBarBackgroundColor = titleBarBackgroundColor;
    [self updateCardTitleBarBackgroundColors];
}

- (void)setTitleFont:(UIFont *)titleFont {
    _titleFont = titleFont;
    for (CardView *card in self.cards) {
        card.titleFont = titleFont;
    }
}

#pragma mark - Getters

- (UIColor *)titleBarBackgroundColor {
    if (_titleBarBackgroundColor) return _titleBarBackgroundColor;

    _titleBarBackgroundColor = [UIColor orangeColor];

    return _titleBarBackgroundColor;
}

- (UIColor *)titleColor {
    if (_titleColor) return _titleColor;

    _titleColor = [UIColor whiteColor];

    return _titleColor;
}

- (UIFont *)titleFont {
    if (_titleFont) return _titleFont;

    _titleFont = [UIFont boldSystemFontOfSize:18.0f];

    return _titleFont;
}

#pragma mark - CardDelegate

- (void)cardTitleTapped:(CardView *)card {
    if (card.tag != self.currentCardIndex) {
        self.isOpen = NO;
        [self setCurrentCardIndex:card.tag animated:YES];
    }
}

- (void)cardRemoveRequested:(CardView *)card {
    if (self.cards.count < 2) {
        return;
    }

    [self removeCardAtIndex:card.tag
                   animated:YES
             withCompletion:nil];
}

- (void)cardTitlePanDidStart:(CardView *)card {
    self.originalCardFrame = card.frame;
}

- (void)card:(CardView *)card titlePannedByDelta:(CGPoint)delta {
    CGFloat y = self.originalCardFrame.origin.y + delta.y;
    if (y >= 0.0f) {
        CGRect frame = self.originalCardFrame;
        frame.origin.y = y;
        card.frame = frame;
        [self updateCardLocationsWhileOpening];
    }
}

- (void)cardTitlePanDidFinish:(CardView *)card withVerticalVelocity:(CGFloat)verticalVelocity {
    if (card.tag == self.currentCardIndex) {
        CGFloat heightAboveCurrentCardWhenOpen = CardStackTopMargin;
        for (NSUInteger i = 0; i < self.currentCardIndex - 1; i++) {
            CardView *card = [self.cards objectAtIndex:i];
            heightAboveCurrentCardWhenOpen += card.titleBarHeight * card.scale;
        }

        self.isOpen = (card.frame.origin.y > heightAboveCurrentCardWhenOpen * CardStackOpenIfLargeThanPercent);

        // if user flicked upwards, close the stack
        if (verticalVelocity < 0.0f) {
            self.isOpen = NO;
        }

        [self updateCardLocationsAnimatedWithVerticalVelocity:verticalVelocity];
    } else {
        if (verticalVelocity < 0.0f && fabs(verticalVelocity) > CardStackVerticalVelocityLimitWhenMakingCardCurrent) {
            // apply animation only to the card being moved (the rest remain stationary)
            POPSpringAnimation *springAnimation = [POPSpringAnimation animationWithPropertyNamed:kPOPViewFrame];
            CGRect frame = [self frameForCardAtIndex:card.tag];
            frame.origin.y = 0;
            springAnimation.toValue = [NSValue valueWithCGRect:frame];
            springAnimation.springBounciness = 8;
            springAnimation.velocity = [NSValue valueWithCGRect:CGRectMake(0, verticalVelocity, 0, 0)];
            springAnimation.completionBlock = ^(POPAnimation *anim, BOOL finished) {
                self.isOpen = NO;
                self.currentCardIndex = self.cards.count - 1;
                [self updateCardScales];
                [self updateCardLocations];
            };
            [card pop_addAnimation:springAnimation forKey:@"frame"];
        } else {
            [self updateCardLocationsAnimated:YES];
        }
    }
}

#pragma mark - Other methods

- (void)insertCardWithViewController:(UIViewController *)viewController
                           withTitle:(NSString *)title
                 aboveViewController:(UIViewController *)aboveViewController
                         makeCurrent:(BOOL)makeCurrent
                            animated:(BOOL)animated
                      withCompletion:(void(^)())completion {
    NSUInteger index = 0;
    for (UIViewController *v in self.viewControllers) {
        if ([v isEqual:aboveViewController]) {
            break;
        }
        ++index;
    }
    if (index == self.viewControllers.count) {
        return;
    }

    NSMutableArray *mutableViewControllers = [self.viewControllers mutableCopy];
    [mutableViewControllers insertObject:viewController atIndex:index];

    // don't user setter to avoid full rebuild
    _viewControllers = [mutableViewControllers copy];

    CardView *aboveCard = [self.cards objectAtIndex:index];
    CardView *card = [CardView cardWithViewController:viewController];
    card.delegate = self;
    card.title = title;
    card.titleFont = self.titleFont;
    card.titleBarBackgroundColor = self.titleBarBackgroundColor;
    NSMutableArray *mutableCards = [self.cards mutableCopy];
    [mutableCards insertObject:card atIndex:index];
    self.cards = [mutableCards copy];
    [self.view insertSubview:card belowSubview:aboveCard];

    // this will make the new card appear from beneath the old card (if the stack is open)
    card.frame = aboveCard.frame;

    if (animated) {
        [UIView animateWithDuration:0.5 animations:^{
            [self updateCardScales];
            [self updateCardLocations];
            [self updateCardTitleBarBackgroundColors];
            if (!makeCurrent) {
                self.currentCardIndex = index + 1;
            }
        } completion:^(BOOL finished) {
            if (completion) {
                completion();
            }
        }];
    } else {
        [self updateCardScales];
        [self updateCardLocations];
        [self updateCardTitleBarBackgroundColors];
        if (!makeCurrent) {
            self.currentCardIndex = index + 1;
        }
        if (completion) {
            completion();
        }
    }
}

- (void)insertCardWithViewController:(UIViewController *)viewController
                           withTitle:(NSString *)title
                 belowViewController:(UIViewController *)belowViewController
                         makeCurrent:(BOOL)makeCurrent
                            animated:(BOOL)animated
                      withCompletion:(void(^)())completion {
    NSUInteger index = 0;
    for (UIViewController *v in self.viewControllers) {
        if ([v isEqual:belowViewController]) {
            break;
        }
        ++index;
    }
    if (index == self.viewControllers.count) {
        return;
    }

    NSMutableArray *mutableViewControllers = [self.viewControllers mutableCopy];
    [mutableViewControllers insertObject:viewController atIndex:index + 1];

    // don't user setter to avoid full rebuild
    _viewControllers = [mutableViewControllers copy];

    CardView *belowCard = [self.cards objectAtIndex:index];
    CardView *card = [CardView cardWithViewController:viewController];
    card.delegate = self;
    card.title = title;
    card.titleFont = self.titleFont;
    card.titleBarBackgroundColor = self.titleBarBackgroundColor;
    NSMutableArray *mutableCards = [self.cards mutableCopy];
    [mutableCards insertObject:card atIndex:index + 1];
    self.cards = [mutableCards copy];
    [self.view insertSubview:card aboveSubview:belowCard];
    if (index == self.currentCardIndex && makeCurrent && animated) {
        // make sure the card animation starts outside of the screen
        CGRect frame = card.frame;
        frame.origin.y = self.view.bounds.size.height;
        card.frame = frame;
    }

    if (animated) {
        [UIView animateWithDuration:0.5 animations:^{
            [self updateCardScales];
            [self updateCardLocations];
            [self updateCardTitleBarBackgroundColors];
            if (makeCurrent) {
                self.currentCardIndex = index + 1;
            }
        } completion:^(BOOL finished) {
            if (completion) {
                completion();
            }
        }];
    } else {
        [self updateCardScales];
        [self updateCardLocations];
        [self updateCardTitleBarBackgroundColors];
        if (makeCurrent) {
            self.currentCardIndex = index + 1;
        }
        if (completion) {
            completion();
        }
    }
}

- (void)removeCardAtIndex:(NSUInteger)index
                 animated:(BOOL)animated
           withCompletion:(void(^)())completion {
    if (self.cards.count < 2 || index > self.cards.count - 1) {
        return;
    }

    // avoid unwanted animation if the topmost card is removed
    if (!self.isOpen) {
        animated = NO;
    }

    NSMutableArray *mutableViewControllers = [self.viewControllers mutableCopy];
    [mutableViewControllers removeObjectAtIndex:index];

    // don't user setter to avoid full rebuild
    _viewControllers = [mutableViewControllers copy];

    __block CardView *card = [self.cards objectAtIndex:index];

    NSMutableArray *mutableCards = [self.cards mutableCopy];
    [mutableCards removeObjectAtIndex:index];
    self.cards = [mutableCards copy];

    if (animated) {
        [UIView animateWithDuration:0.5 animations:^{
            if (self.cards.count == 1 && self.isOpen) {
                self.isOpen = NO;
            }
            [self updateCardScales];
            [self updateCardLocations];
            [self updateCardTitleBarBackgroundColors];
            if (self.currentCardIndex > 0 && self.currentCardIndex > self.cards.count - 1) {
                self.currentCardIndex = self.cards.count - 1;
            }

            CGRect frame = card.frame;
            frame.origin.x = frame.origin.x + self.view.bounds.size.width;
            card.frame = frame;
        } completion:^(BOOL finished) {
            // removal is diferred, so a proper removal animation could be executed
            [card removeFromSuperview];

            if (completion) {
                completion();
            }
        }];
    } else {
        if (self.cards.count == 1 && self.isOpen) {
            self.isOpen = NO;
        }
        [self updateCardScales];
        [self updateCardLocations];
        [self updateCardTitleBarBackgroundColors];
        if (self.currentCardIndex > 0 && self.currentCardIndex > self.cards.count - 1) {
            self.currentCardIndex = self.cards.count - 1;
        }
        [card removeFromSuperview];
        if (completion) {
            completion();
        }
    }
}

- (void)updateCardScales {
    NSUInteger index = 0;
    for (CardView *card in self.cards) {
        CGFloat scale = 1.0f;
        if (index < self.currentCardIndex) {
            NSInteger relativeIndex = index - self.currentCardIndex;
            scale = 1.0 + relativeIndex * CardStackDepthOffset;
        }
        card.scale = scale;
        ++index;
    }
}

- (void)updateCardTitleBarBackgroundColors {
    UIColor *titleBarBackgroundColor = self.titleBarBackgroundColor;
    CGFloat red;
    CGFloat green;
    CGFloat blue;
    [titleBarBackgroundColor getRed:&red green:&green blue:&blue alpha:nil];

    for (NSUInteger i = 0; i < self.cards.count; i++) {
        NSInteger offset = (i - self.cards.count + 1);
        CGFloat colorOffset = offset * CardStackTitleBarBackgroundColorOffset;
        UIColor *modifiedColor = [UIColor colorWithRed:red + colorOffset green:green + colorOffset blue:blue + colorOffset alpha:1.0];
        CardView *card = [self.cards objectAtIndex:i];
        card.titleBarBackgroundColor = modifiedColor;
    }
}

- (void)updateCardLocations {
    [self updateCardLocationsAnimated:NO];
}

- (void)updateCardLocationsAnimated:(BOOL)animated {
    if (animated) {
        [self updateCardLocationsAnimatedWithVerticalVelocity:0.0f];
    } else {
        for (NSUInteger i = 0; i < self.cards.count; i++) {
            CardView *card = [self.cards objectAtIndex:i];
            card.frame = [self frameForCardAtIndex:i];
        }
    }
}

- (void)updateCardLocationsAnimatedWithVerticalVelocity:(CGFloat)verticalVelocity {
    for (NSUInteger i = 0; i < self.cards.count; i++) {
        CardView *card = [self.cards objectAtIndex:i];
        POPSpringAnimation *springAnimation = [POPSpringAnimation animationWithPropertyNamed:kPOPViewFrame];
        CGRect frame = [self frameForCardAtIndex:i];
        springAnimation.toValue = [NSValue valueWithCGRect:frame];
        springAnimation.springBounciness = 8;

        if (verticalVelocity > 0.0f && i <= self.currentCardIndex) {
            // scale down velocity for upper cards to avoid unwanted spring effect
            CGFloat springVelocity = (verticalVelocity * card.scale) * ((CGFloat)i / (CGFloat)(self.currentCardIndex + 1));
            springAnimation.velocity = [NSValue valueWithCGRect:CGRectMake(0, springVelocity, 0, 0)];
        }

        [card pop_addAnimation:springAnimation forKey:@"frame"];
    }
}

- (void)updateCardLocationsWhileOpening {
    if (self.currentCardIndex > 0) {
        CGFloat startY = CardStackTopMargin;
        CardView *currentCard = [self.cards objectAtIndex:self.currentCardIndex];
        CGFloat endY = currentCard.frame.origin.y;
        CGFloat currentY = startY;
        CGFloat incrementY = (endY - startY) / self.currentCardIndex;
        for (NSUInteger i = 0; i < self.currentCardIndex; i++) {
            currentCard = [self.cards objectAtIndex:i];
            CGRect frame = currentCard.frame;
            frame.origin.y = currentY;
            currentCard.frame = frame;
            currentY = currentY + incrementY;
        }
    }
}

- (CGRect)frameForCardAtIndex:(NSUInteger)index {
    CGRect frame;

    if (index <= self.currentCardIndex) {
        if (self.isOpen) {
            CGFloat previousTitleBarHeights = CardStackTopMargin;
            for (NSUInteger i = 0; i < index; i++) {
                CardView *card = [self.cards objectAtIndex:i];

                // -1.0f is used to avoid area below the title bar to become slightly visible is some cases (due to rounding errors)
                previousTitleBarHeights += (card.titleBarHeight * card.scale - 1.0f);
            }

            CardView *card = [self.cards objectAtIndex:index];
            frame = card.frame;
            frame.origin.y = previousTitleBarHeights;
        } else {
            CardView *card = [self.cards objectAtIndex:index];
            frame = card.frame;
            frame.origin.y = 0;
        }
    } else if (index > self.currentCardIndex && index < self.cards.count - 1) {
        CardView *card = [self.cards objectAtIndex:index];
        frame = card.frame;
        frame.origin.y = self.view.bounds.size.height;
    } else {
        CardView *card = [self.cards objectAtIndex:index];
        frame = card.frame;
        frame.origin.y = self.view.bounds.size.height - card.titleBarHeight;
    }

    return frame;
}

@end
