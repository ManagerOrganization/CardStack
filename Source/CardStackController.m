#import "CardStackController.h"
#import "Card.h"

@interface CardStackController () <CardDelegate>

@property (nonatomic) NSArray *cards;
@property (nonatomic) BOOL isAnimating;
@property (nonatomic) BOOL isOpen;

@end

@implementation CardStackController

#pragma mark - Setters

- (void)setViewControllers:(NSArray *)viewControllers
{
#warning TODO: remove old title bar image views
#warning TODO: remove old title labels
#warning TODO: remove old cards

    for (Card *card in self.cards) {
        [card.viewController.view removeFromSuperview];
    }

    self.cards = [Card cardsWithViewControllers:viewControllers
                                  titleBarImage:self.titleBarImage
                    titleBarImageVerticalOffset:self.titleBarImageVerticalOffset
                                     titleColor:self.titleColor
                                      titleFont:self.titleFont];

    self.currentCardIndex = self.cards.count - 1;
}

#pragma mark - Getters

- (UIColor *)titleColor
{
    if (_titleColor) return _titleColor;

    _titleColor = [UIColor whiteColor];

    return _titleColor;
}

- (UIFont *)titleFont
{
    if (_titleFont) return _titleFont;

    _titleFont = [UIFont boldSystemFontOfSize:18.0f];

    return _titleFont;
}

#pragma mark - Setters

- (void)setCurrentCardIndex:(NSUInteger)currentCardIndex
{
    _currentCardIndex = currentCardIndex;

    [self updateCardScales];
    [self updateCardLocations];
}

- (void)setCurrentCardIndex:(NSUInteger)currentCardIndex animated:(BOOL)animated
{
    if (animated) {
        [UIView animateWithDuration:0.5 animations:^{
            self.currentCardIndex = currentCardIndex;
        } completion:nil];
    } else {
        self.currentCardIndex = currentCardIndex;
    }
}

#pragma mark - CardDelegate

- (void)cardTitleTapped:(Card *)card
{
    NSUInteger index = 0;
    for (Card *c in self.cards) {
        if ([c isEqual:card]) {
            break;
        }
        ++index;
    }

    if (index == self.currentCardIndex) {
        if (index > 0) {
            [self openStackAnimated:YES withCompletion:^{
                [self.delegate cardStackControllerDidOpen:self];
            }];
        }
    } else {
        self.isOpen = NO;
        [self setCurrentCardIndex:index animated:YES];
    }
}

#pragma mark - Other methods

- (void)openStackAnimated:(BOOL)animated
           withCompletion:(void(^)())completion
{
    if (self.isAnimating) {
        return;
    }

    self.isAnimating = YES;
    self.isOpen = YES;
    [UIView animateWithDuration:0.5 animations:^{
        [self updateCardLocations];
    } completion:^(BOOL finished) {
        self.isAnimating = NO;
        if (completion) {
            completion();
        }
    }];
}

- (void)closeStackAnimated:(BOOL)animated
            withCompletion:(void(^)())completion
{
    if (self.isAnimating) {
        return;
    }

    self.isAnimating = YES;
    self.isOpen = NO;
    [UIView animateWithDuration:0.5 animations:^{
        [self updateCardLocations];
    } completion:^(BOOL finished) {
        self.isAnimating = NO;
        if (completion) {
            completion();
        }
    }];
}

- (void)updateTitles
{
    for (Card *card in self.cards) {
        card.titleLabel.text = card.viewController.title;
    }
}

- (void)updateCardScales
{
    NSUInteger index = 0;
    for (Card *card in self.cards) {
        card.delegate = self;

        [self.view addSubview:card.viewController.view];

        CGFloat scale = 1.0f;
        if (index < self.currentCardIndex) {
            NSInteger relativeIndex = index - self.currentCardIndex;
            scale = 1.0 + relativeIndex * 0.04;
        }
        card.scale = scale;
        card.viewController.view.layer.transform = CATransform3DMakeScale(card.scale, card.scale, 1.0);

        ++index;
    }
}

- (void)updateCardLocations
{
    if (self.isOpen) {
        CGFloat previousTitleBarHeights = 0.0f;
        for (NSUInteger i = 0; i < self.cards.count; i++) {
            Card *card = [self.cards objectAtIndex:i];
            UIViewController *viewController = card.viewController;

            CGRect frame = viewController.view.frame;
            if (i <= self.currentCardIndex) {
                frame.origin.y = previousTitleBarHeights + 10;
            } else {
                frame.origin.y = self.view.bounds.size.height - self.titleBarImage.size.height;
            }
            viewController.view.frame = frame;

            previousTitleBarHeights += [card scaledTitleBarHeight];
        }
    } else {
        for (NSUInteger i = 0; i < self.cards.count; i++) {
            Card *card = [self.cards objectAtIndex:i];
            UIViewController *viewController = card.viewController;

            CGRect frame = viewController.view.frame;
            if (i <= self.currentCardIndex) {
                frame.origin.y = 0;
            } else {
                frame.origin.y = self.view.bounds.size.height - (self.titleBarImage.size.height + self.titleBarImageVerticalOffset);
            }
            viewController.view.frame = frame;
        }
    }
}

@end
