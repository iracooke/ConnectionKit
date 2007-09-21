/*
 Copyright (c) 2007, Ubermind, Inc
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Ubermind, Inc nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 Authored by Greg Hulands <ghulands@mac.com>
 */

#import "CKTableBasedBrowser.h"
#import <Carbon/Carbon.h>

@class CKResizingButton;
@class CKDirectoryBrowserCell;

@interface CKBrowserTableView : NSTableView
{
	NSMutableString *myQuickSearchString;
}
@end

@interface NSObject (CKBrowserTableViewDelegateExtensions)
- (void)tableView:(NSTableView *)tableView deleteRows:(NSArray *)rows;
- (void)tableView:(NSTableView *)tableView didKeyPress:(NSString *)partialSearch;
- (NSMenu *)tableView:(NSTableView *)tableView contextMenuForEvent:(NSEvent *)theEvent;
- (void)tableViewNavigateForward:(NSTableView *)tableView;
- (void)tableViewNavigateBackward:(NSTableView *)tableView;

@end

@interface CKTableBrowserScrollView : NSScrollView
{
	CKResizingButton *myResizer;
	
	struct __cktv_flags {
		unsigned canResize: 1;
		unsigned unused: 1;
	} myFlags;
}

- (void)setCanResize:(BOOL)flag;
- (BOOL)canResize;
- (CKResizingButton *)resizer;

@end

@interface CKTableBasedBrowser (Private)

- (void)reflowColumns;
- (NSString *)parentPathOfPath:(NSString *)path;
- (NSString *)parentPathOfItem:(id)item;
- (id)parentOfItem:(id)item;
- (void)updateScrollers;
- (void)tableSelectedCell:(id)sender notifyTarget:(BOOL)flag;
- (unsigned)rowForItem:(id)item;

@end

#define SCROLLER_WIDTH 16.0

static Class sCellClass = nil;

@implementation CKTableBasedBrowser

+ (void)initialize
{
	sCellClass = [CKDirectoryBrowserCell class];
}

+ (Class)cellClass
{
	return sCellClass;
}

- (id)initWithFrame:(NSRect)rect
{
	if ((self != [super initWithFrame:rect]))
	{
		[self release];
		return nil;
	}
	
	[self setCellClass:[CKTableBasedBrowser class]];
	myColumns = [[NSMutableArray alloc] initWithCapacity:8];
	myColumnWidths = [[NSMutableDictionary alloc] initWithCapacity:8];
	mySelection = [[NSMutableArray alloc] initWithCapacity:32];
	
	myAutosaveName = @"Default";
	myPathSeparator = @"/";
	myCurrentPath = @"/";
	
	myMinColumnWidth = 180;
	myMaxColumnWidth = -1;
	myRowHeight = 18;
	myDefaultColumnWidth = -1;
	
	myFlags.allowsMultipleSelection = NO;
	myFlags.allowsResizing = YES;
	myFlags.isEditable = NO;
	myFlags.isEnabled = YES;
	
	return self;
}

- (void)dealloc
{
	[myColumns release];
	[myColumnWidths release];
	[mySelection release];
	[myCellPrototype release];
	[myAutosaveName release];
	[myPathSeparator release];
	
	[super dealloc];
}

- (void)drawRect:(NSRect)rect
{
	[[NSColor whiteColor] set];
	NSRectFill(rect);
}

- (void)setCellClass:(Class)aClass
{
	myCellClass = aClass;
}

- (id)cellPrototype
{
	return myCellPrototype;
}

- (void)setCellPrototype:(id)prototype
{
	[myCellPrototype autorelease];
	myCellPrototype = [prototype retain];
}

- (void)setEnabled:(BOOL)flag
{
	if (myFlags.isEnabled != flag)
	{
		myFlags.isEnabled = flag;
		
		// go through and dis/en able things
		NSEnumerator *e = [myColumns objectEnumerator];
		NSTableView *cur;
		
		while ((cur = [e nextObject]))
		{
			[cur setEnabled:flag];
			[[[cur enclosingScrollView] verticalScroller] setEnabled:flag];
		}
	}
}

- (BOOL)isEnabled
{
	return myFlags.isEnabled;
}

- (void)setAllowsMultipleSelection:(BOOL)flag
{
	if (myFlags.allowsMultipleSelection != flag)
	{
		myFlags.allowsMultipleSelection = flag;
		
		if (myFlags.allowsMultipleSelection)
		{
			// we need to make sure that the current selection(s) hold to the new rule
			
		}
	}
}

- (BOOL)allowsMultipleSelection
{
	return myFlags.allowsMultipleSelection;
}

- (void)setAllowsColumnResizing:(BOOL)flag
{
	if (myFlags.allowsResizing != flag)
	{
		myFlags.allowsResizing = flag;
		
		//update the current columns
		NSEnumerator *e = [myColumns objectEnumerator];
		NSTableView *cur;
		
		while ((cur = [e nextObject]))
		{
			[(CKTableBrowserScrollView *)[cur enclosingScrollView] setCanResize:myFlags.allowsResizing];
		}
	}
}

- (BOOL)allowsColumnResizing
{
	return myFlags.allowsResizing;
}

- (void)setEditable:(BOOL)flag
{
	if (myFlags.isEditable != flag)
	{
		myFlags.isEditable = flag;
		
		// update the table views to make sure their columns aren't editable
		NSEnumerator *e = [myColumns objectEnumerator];
		NSTableView *cur;
		
		while ((cur = [e nextObject]))
		{
			NSEnumerator *f = [[cur tableColumns] objectEnumerator];
			NSTableColumn *col;
			
			while ((col = [f nextObject]))
			{
				[col setEditable:flag];
			}
		}
	}
}

- (BOOL)isEditable
{
	return myFlags.isEditable;
}

- (void)setRowHeight:(float)height
{
	myRowHeight = height;
	
	// update all current cols
	NSEnumerator *e = [myColumns objectEnumerator];
	NSTableView *cur;
	
	while ((cur = [e nextObject]))
	{
		[cur setRowHeight:myRowHeight];
	}
}

- (float)rowHeight
{
	return myRowHeight;
}

- (void)setMinColumnWidth:(float)size
{
	if (myMinColumnWidth > myMaxColumnWidth)
	{
		myMaxColumnWidth = size;
	}
	myMinColumnWidth = size;
	
	[self reflowColumns];
}

- (float)minColumnWidth
{
	return myMinColumnWidth;
}

- (void)setMaxColumnWidth:(float)size
{
	if (myMaxColumnWidth < myMinColumnWidth)
	{
		myMinColumnWidth = size;
	}
	myMaxColumnWidth = size;
	
	[self reflowColumns];
}

- (float)maxColumnWidth
{
	return myMaxColumnWidth;
}

- (void)setPathSeparator:(NSString *)sep
{
	if (myPathSeparator != sep)
	{
		[myPathSeparator autorelease];
		myPathSeparator = [sep copy];
	}
}

- (NSString *)pathSeparator
{
	return myPathSeparator;
}

- (void)selectAll:(id)sender
{
	if (myFlags.allowsMultipleSelection)
	{
		// TODO
	}
}

- (void)selectItem:(id)item
{
	[self selectItems:[NSArray arrayWithObject:item]];
}

- (void)selectItems:(NSArray *)items
{
	unsigned i, c = [items count];
	
	// remove current selection
	[mySelection removeAllObjects];
	if ([myColumns count] > 0)
	{
		// only need to deselect everything in the first column as other columns will auto refresh
		// [[myColumns objectAtIndex:0] deselectAll:self]; 
	}
	
	NSTableView *firstSelectedItemColumn = nil;
	
	if ([items count] > 0)
	{
		unsigned col, row;
		id item = [items objectAtIndex:0];
		
		[self column:&col row:&row forItem:item];
		
		if (col != NSNotFound)
		{
			firstSelectedItemColumn = [myColumns objectAtIndex:col];
			[firstSelectedItemColumn deselectAll:self];
		}
	}
	
	for (i = 0; i < c; i++)
	{
		id item = [items objectAtIndex:i];
		unsigned col, row;
		
		[self column:&col row:&row forItem:item];
		
		if (col != NSNotFound)
		{
			NSTableView *column = [myColumns objectAtIndex:col];
			if (column == firstSelectedItemColumn) // we can only multiselect in the same column
			{
				[column selectRow:row byExtendingSelection:myFlags.allowsMultipleSelection];
				[self tableSelectedCell:column notifyTarget:NO];
			}
		}
	}
}

- (NSArray *)selectedItems
{
	return [NSArray arrayWithArray:mySelection];
}

- (void)setPath:(NSString *)path
{
	[mySelection removeAllObjects];
	
	if (path)
	{
		id item = [myDataSource tableBrowser:self itemForPath:path];
		if (item)
		{
			// enumerate over the path and simulate table clicks
			NSString *separator = [self pathSeparator];
			NSRange r = [path rangeOfString:separator];
			unsigned row, col;
			
			while (r.location != NSNotFound)
			{
				NSString *bit = [path substringToIndex:r.location];
				[self column:&col row:&row forItem:[myDataSource tableBrowser:self itemForPath:bit]];
				
				if (col != NSNotFound && row != NSNotFound)
				{
					NSTableView *column = [myColumns objectAtIndex:col];
					[column selectRow:row byExtendingSelection:NO];
					[self tableSelectedCell:column notifyTarget:NO];
					[column scrollRowToVisible:row];
				}
				
				
				r = [path rangeOfString:separator options:NSLiteralSearch range:NSMakeRange(NSMaxRange(r), [path length] - NSMaxRange(r))];
			}
			// now do the last path component
			[self column:&col row:&row forItem:item];
			if (col != NSNotFound && row != NSNotFound)
			{
				NSTableView *column = [myColumns objectAtIndex:col];
				[column selectRow:row byExtendingSelection:NO];
				[self tableSelectedCell:column notifyTarget:NO];
				[column scrollRowToVisible:row];
				[[self window] makeFirstResponder:column];
			}
		}
	}
}

- (NSString *)path
{
	if ([mySelection count] == 0) return nil;
	
	id item = [mySelection lastObject];
	NSString *path = nil;
	
	if (item)
	{
		path = [myDataSource tableBrowser:self pathForItem:item];
	}
	
	return path;
}

- (void)setTarget:(id)target
{
	myTarget = target;
}

- (id)target
{
	return myTarget;
}

- (void)setAction:(SEL)anAction
{
	myAction = anAction;
}

- (SEL)action
{
	return myAction;
}

- (void)setDoubleAction:(SEL)anAction
{
	myDoubleAction = anAction;
}

- (SEL)doubleAction
{
	return myDoubleAction;
}

- (void)setDataSource:(id)ds
{
	if (![ds respondsToSelector:@selector(tableBrowser:numberOfChildrenOfItem:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"dataSource must implement tableBrowser:numberOfChildrenOfItem:" userInfo:nil];
	}
	if (![ds respondsToSelector:@selector(tableBrowser:child:ofItem:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"dataSource must implement tableBrowser:child:ofItem:" userInfo:nil];
	}
	if (![ds respondsToSelector:@selector(tableBrowser:isItemExpandable:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"dataSource must implement tableBrowser:isItemExpandable:" userInfo:nil];
	}
	if (![ds respondsToSelector:@selector(tableBrowser:objectValueByItem:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"dataSource must implement tableBrowser:objectValueByItem:" userInfo:nil];
	}
	if (![ds respondsToSelector:@selector(tableBrowser:pathForItem:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"dataSource must implement tableBrowser:pathForItem:" userInfo:nil];
	}
	if (![ds respondsToSelector:@selector(tableBrowser:itemForPath:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"dataSource must implement tableBrowser:itemForPath:" userInfo:nil];
	}
	myDataSourceFlags.numberOfChildrenOfItem = YES;
	myDataSourceFlags.childOfItem = YES;
	myDataSourceFlags.isItemExpandable = YES;
	myDataSourceFlags.objectValueByItem = YES;
	myDataSourceFlags.itemForPath = YES;
	myDataSourceFlags.pathForItem = YES;
	
	// these are optionals
	myDataSourceFlags.setObjectValueByItem = [ds respondsToSelector:@selector(tableBrowser:setObjectValue:byItem:)];
	myDataSourceFlags.acceptDrop = [ds respondsToSelector:@selector(tableBrowser:acceptDrop:item:childIndex:)];
	myDataSourceFlags.validateDrop = [ds respondsToSelector:@selector(tableBrowser:validateDrop:proposedItem:proposedChildIndex:)];
	myDataSourceFlags.writeItemsToPasteboard = [ds respondsToSelector:@selector(tableBrowser:writeItems:toPasteboard:)];
		
	myDataSource = ds;
	
	[self updateScrollers];
	[self reloadData];
}

- (id)dataSource
{
	return myDataSource;
}

- (void)setDelegate:(id)delegate
{
	myDelegateFlags.shouldExpandItem = [delegate respondsToSelector:@selector(tableBrowser:shouldExpandItem:)];
	myDelegateFlags.shouldSelectItem = [delegate respondsToSelector:@selector(tableBrowser:shouldSelectItem:)];
	myDelegateFlags.willDisplayCell = [delegate respondsToSelector:@selector(tableBrowser:willDisplayCell:item:)];
	myDelegateFlags.tooltipForCell = [delegate respondsToSelector:@selector(tableBrowser:toolTipForCell:rect:item:mouseLocation:)];
	myDelegateFlags.shouldEditItem = [delegate respondsToSelector:@selector(tableBrowser:shouldEditItem:)];
	myDelegateFlags.leafViewWithItem = [delegate respondsToSelector:@selector(tableBrowser:leafViewWithItem:)];
	myDelegateFlags.contextMenuWithItem = [delegate respondsToSelector:@selector(tableBrowser:contextMenuWithItem:)];
	
	myDelegate = delegate;
}

- (id)delegate
{
	return myDelegate;
}

- (BOOL)isExpandable:(id)item
{
	return [myDataSource tableBrowser:self isItemExpandable:item];
}

- (void)expandItem:(id)item
{
	if ([self isExpandable:item])
	{
		// TODO
	}
}

- (unsigned)columnWithTable:(NSTableView *)table
{
	return [myColumns indexOfObjectIdenticalTo:table];
}


- (NSString *)pathToColumn:(unsigned)column
{
	NSString *separator = [self pathSeparator];
	if (myCurrentPath == nil || [myCurrentPath isEqualToString:separator] || (int)column <= 0) return separator;
	
	NSMutableString *path = [NSMutableString stringWithString:separator];
	NSRange range = [myCurrentPath rangeOfString:separator];
	NSRange lastRange = NSMakeRange(0, [separator length]);
	unsigned i;
	
	for (i = 0; i < column; i++)
	{
		//if (range.location == NSNotFound) return nil; // incase the column requested is invalid compared to the current path
		range = [myCurrentPath rangeOfString:separator options:NSLiteralSearch range:NSMakeRange(NSMaxRange(range), [myCurrentPath length] - NSMaxRange(range))];
		NSRange componentRange;
		
		if (range.location == NSNotFound)
		{
			componentRange = NSMakeRange(NSMaxRange(lastRange), [myCurrentPath length] - NSMaxRange(lastRange));
		}
		else
		{
			componentRange = NSMakeRange(NSMaxRange(lastRange), NSMaxRange(range) - NSMaxRange(lastRange));
		}
		
		[path appendString:[myCurrentPath substringWithRange:componentRange]];
		lastRange = range;
	}
		
	return path;
}

- (unsigned)columnToItem:(id)item
{
	NSString *itemPath = [myDataSource tableBrowser:self pathForItem:item];
	BOOL isItemVisible = NO;
	
	// see if the path is visible
	NSString *parentPath = [self parentPathOfPath:itemPath];
	if ([myCurrentPath hasPrefix:parentPath])
	{
		isItemVisible = YES;
	}
	
	unsigned column = NSNotFound;
	
	if (isItemVisible)
	{
		unsigned i, c = [myColumns count];
		
		for (i = 0; i < c; i++)
		{
			if ([[self pathToColumn:i] isEqualToString:parentPath])
			{
				column = i;
				break;
			}
		}
	}
	
	
	return column;
}

- (id)createColumnWithRect:(NSRect)rect
{
	CKTableBrowserScrollView *scroller = [[CKTableBrowserScrollView alloc] initWithFrame:rect];
	[scroller setHasVerticalScroller:YES];
	[scroller setHasHorizontalScroller:NO];
	[[scroller resizer] setDelegate:self];
	[scroller setAutoresizingMask: NSViewHeightSizable];
	
	CKBrowserTableView *table = [[CKBrowserTableView alloc] initWithFrame:[scroller documentVisibleRect]];
	[scroller setDocumentView:table];
	[myColumns addObject:table];
	[table setAutoresizingMask:NSViewHeightSizable];
	[table setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
	[table release];
	
	// configure table
	NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"ckbrowser"];
	[col setEditable:myFlags.isEditable];
	if ([self cellPrototype])
	{
		[col setDataCell:[self cellPrototype]];
	}
	else
	{
		NSCell *cell = [[myCellClass alloc] initTextCell:@""];
		[col setDataCell:cell];
		[cell release];
	}
	[table setAllowsEmptySelection:YES];
	[table setHeaderView:nil];
	[table addTableColumn:col];
	[col setWidth:NSWidth([table frame])];
	[table setTarget:self];
	[table setAction:@selector(tableSelectedCell:)];
	[table setAllowsColumnResizing:NO];
	[table setAllowsColumnReordering:NO];
	[table setAllowsColumnSelection:NO];
	[table setAllowsMultipleSelection:myFlags.allowsMultipleSelection];
	[table setRowHeight:myRowHeight];
	[table setFocusRingType:NSFocusRingTypeNone];
	
	[col release];
	
	[table setDataSource:self];
	[table setDelegate:self];
	
	return scroller;
}

- (void)updateScrollers
{
	// get the total width of the subviews
	float maxX = 0;
	
	if (myLeafView)
	{
		maxX = NSMaxX([[myLeafView enclosingScrollView] frame]);
	}
	else
	{
		maxX = NSMaxX([[[myColumns lastObject] enclosingScrollView] frame]);
	}

	NSRect docArea = [[self enclosingScrollView] documentVisibleRect];
	NSRect bounds = NSMakeRect(0, 0, maxX, NSHeight(docArea));
	
	if (maxX < NSWidth(docArea))
	{
		bounds.size.width = NSWidth(docArea);
	}
	
	[self setFrameSize:bounds.size];
}

- (void)reloadData
{
	// load the first column and then subsequent columns based on the myCurrentPath
	NSRect bounds = [[self enclosingScrollView] documentVisibleRect];
	NSRect columnRect = NSMakeRect(0, 0, myMinColumnWidth, NSHeight(bounds));
	
	// if required create column, then reload the data
	NSArray *pathComponents = [myCurrentPath componentsSeparatedByString:[self pathSeparator]];
	if ([myCurrentPath isEqualToString:[self pathSeparator]])
	{
		pathComponents = [pathComponents subarrayWithRange:NSMakeRange(1, [pathComponents count] - 1)];
	}
	
	unsigned i, c = [pathComponents count];
	
	for (i = 0; i < c; i++)
	{
		if (i >= [myColumns count])
		{
			// see if there is a custom width
			if ([myColumnWidths objectForKey:[NSNumber numberWithUnsignedInt:i]])
			{
				columnRect.size.width = [[myColumnWidths objectForKey:[NSNumber numberWithUnsignedInt:i]] floatValue];
			}
			else if (myDefaultColumnWidth > 0)
			{
				columnRect.size.width = myDefaultColumnWidth;
			}
			else
			{
				columnRect.size.width = myMinColumnWidth;
			}
			
			// create the column
			NSScrollView *col = [self createColumnWithRect:columnRect];
			[self addSubview:col];
		}
		NSTableView *column = [myColumns objectAtIndex:i];
		[column reloadData];
		columnRect.origin.x += NSWidth([[column enclosingScrollView] frame]) + 1;
	}
	
	// update the horizontal scroller
	[self updateScrollers];
	
	// if there are any columns that aren't needed anymore, remove them
	for (i = c; i < [myColumns count]; i++)
	{
		NSScrollView *col = [[myColumns objectAtIndex:i] enclosingScrollView];
		[col removeFromSuperview];
	}
	[myColumns removeObjectsInRange:NSMakeRange(c, [myColumns count] - c)];
	
	[self updateScrollers];
}

- (void)reloadItem:(id)item
{
	unsigned column = [self columnToItem:item];
	if (column != NSNotFound)
	{
		[[myColumns objectAtIndex:column] reloadData];
	}
}

- (void)reloadItem:(id)item reloadChildren:(BOOL)flag
{
	[self reloadItem:item];
	
	// TODO - reload children
}

- (id)itemAtColumn:(unsigned)column row:(unsigned)row
{
	return nil;
}

- (NSString *)parentPathOfPath:(NSString *)path
{
	NSRange r = [path rangeOfString:[self pathSeparator] options:NSBackwardsSearch];
	
	if (r.location != NSNotFound)
	{
		path = [path substringToIndex:r.location];
	}
	
	if ([path isEqualToString:@""]) path = [self pathSeparator];
	
	return path;
}

- (NSString *)parentPathOfItem:(id)item
{
	NSString *path = [myDataSource tableBrowser:self pathForItem:item];
	return [self parentPathOfPath:path];
}

- (id)parentOfItem:(id)item
{
	return [myDataSource tableBrowser:self itemForPath:[self parentPathOfItem:item]];
}

- (unsigned)rowForItem:(id)item
{
	id parent = [self parentOfItem:item];
	unsigned i, c = [myDataSource tableBrowser:self numberOfChildrenOfItem:parent];
	for (i = 0; i < c; i++)
	{
		if ([myDataSource tableBrowser:self child:i ofItem:parent] == item)
		{
			return i;
		}
	}
	return NSNotFound;
}

- (void)column:(unsigned *)column row:(unsigned *)row forItem:(id)item
{
	unsigned col = [self columnToItem:item];
	unsigned r = [self rowForItem:item];
	
	if (column) *column = col;
	if (row) *row = r;
}

- (void)setAutosaveName:(NSString *)name
{
	if (myAutosaveName != name)
	{
		[myAutosaveName autorelease];
		myAutosaveName = [name copy];
	}
}

- (NSString *)autosaveName
{
	return myAutosaveName;
}

- (void)scrollItemToVisible:(id)item
{
	
}

- (NSRect)frameOfColumnContainingItem:(id)item
{
	return NSZeroRect;
}

- (void)leafInspectItem:(id)item
{
	if (myDelegateFlags.leafViewWithItem)
	{
		myLeafView = [myDelegate tableBrowser:self leafViewWithItem:item];
		if (myLeafView)
		{
			NSRect lastColumnFrame = [[[myColumns lastObject] enclosingScrollView] frame];
			lastColumnFrame.origin.x = NSMaxX(lastColumnFrame) + 1;
			
			// get the custom width for the column
			if ([myColumnWidths objectForKey:[NSNumber numberWithUnsignedInt:[myColumns count]]])
			{
				lastColumnFrame.size.width = [[myColumnWidths objectForKey:[NSNumber numberWithUnsignedInt:[myColumns count]]] floatValue];
			}
			else if (myDefaultColumnWidth > 0)
			{
				lastColumnFrame.size.width = myDefaultColumnWidth;
			}
			else if (NSWidth([myLeafView frame]) + SCROLLER_WIDTH > NSWidth(lastColumnFrame))
			{
				lastColumnFrame.size.width = NSWidth([myLeafView frame]) + SCROLLER_WIDTH;
			}
			
			[myColumnWidths setObject:[NSNumber numberWithFloat:NSWidth(lastColumnFrame)] forKey:[NSNumber numberWithUnsignedInt:[myColumns count]]];
			
			// create a scroller for it as well
			CKTableBrowserScrollView *scroller = [[CKTableBrowserScrollView alloc] initWithFrame:lastColumnFrame];
			[scroller setHasVerticalScroller:YES];
			[scroller setHasHorizontalScroller:NO];
			[[scroller resizer] setDelegate:self];
			[scroller setAutoresizingMask: NSViewHeightSizable];
			
			if (NSHeight([myLeafView frame]) > NSHeight(lastColumnFrame))
			{
				lastColumnFrame.size.height = NSHeight([myLeafView frame]);
			}
			lastColumnFrame.size.width -= SCROLLER_WIDTH;
			[myLeafView setFrame:lastColumnFrame];
			
			[scroller setDocumentView:myLeafView];
			[myLeafView scrollRectToVisible:NSMakeRect(0,NSMaxY(lastColumnFrame) - 1,1,1)];
			[self addSubview:scroller];
			[scroller release];
			[self updateScrollers];
			
			// scroll it to visible
			lastColumnFrame.size.width += SCROLLER_WIDTH;
			[self scrollRectToVisible:lastColumnFrame];
		}
	}
}

- (void)tableSelectedCell:(id)sender notifyTarget:(BOOL)flag
{
	id lastSelectedItem = [mySelection lastObject];
	
	if (!myFlags.allowsMultipleSelection)
	{
		[mySelection removeAllObjects];
	}
	
	int column = [self columnWithTable:sender];
	int row = [sender selectedRow];
	
	NSString *path = [self pathToColumn:column];
	id containerItem = [myDataSource tableBrowser:self itemForPath:path];
	id item = [myDataSource tableBrowser:self child:row ofItem:containerItem];
	BOOL isDirectory = [myDataSource tableBrowser:self isItemExpandable:item];
	
	//NSLog(@"%d = %@", column, [item path]);
	/*
	 Selection Changes handled
	 - selection is going to drill down into a directory
	 - selection is above the current directory
	 - selection is in the current directory
	 - multiple selection is maintained to the last column
	 */
	id currentContainerItem = nil;
	if (lastSelectedItem)
	{
		currentContainerItem = [self parentOfItem:lastSelectedItem];
	}
	else
	{
		currentContainerItem = [myDataSource tableBrowser:self itemForPath:path];
	}
	
	// remove the leaf view if it is visible
	[[myLeafView enclosingScrollView] removeFromSuperview];
	myLeafView = nil;
	
	// remove columns greater than the currently selected one
	unsigned i;
	if ([myColumns count] > column + 1)
	{
		for (i = column + 1; i < [myColumns count]; i++)
		{
			NSTableView *table = [myColumns objectAtIndex:i];
			NSScrollView *scroller = [table enclosingScrollView];
			[table setDataSource:nil];
			[scroller removeFromSuperview];
		}
		NSRange r = NSMakeRange(column + 1, i - column - 1);
		[myColumns removeObjectsInRange:r];
	}
	
	if (isDirectory)
	{
		[myCurrentPath autorelease];
		myCurrentPath = [[myDataSource tableBrowser:self pathForItem:item] copy];
		
		// since we have gone into a new dir, any selections, even in a multi selection are now invalid
		[mySelection removeAllObjects];
		[mySelection addObject:item];
		
		// create a new column
		NSRect lastColumnFrame = [[[myColumns lastObject] enclosingScrollView] frame];
		lastColumnFrame.origin.x = NSMaxX(lastColumnFrame) + 1;
		
		// see if there is a custom column width
		if ([myColumnWidths objectForKey:[NSNumber numberWithUnsignedInt:[myColumns count]]])
		{
			lastColumnFrame.size.width = [[myColumnWidths objectForKey:[NSNumber numberWithUnsignedInt:[myColumns count]]] floatValue];
		}
		else if (myDefaultColumnWidth > 0)
		{
			lastColumnFrame.size.width = myDefaultColumnWidth;
		}
		else
		{
			lastColumnFrame.size.width = myMinColumnWidth;
		}
		
		id newColumn = [self createColumnWithRect:lastColumnFrame];
		[self addSubview:newColumn];
		[self updateScrollers];
		
		[self scrollRectToVisible:lastColumnFrame];
	}
	else
	{
		// add to the current selection
		[mySelection addObject:item];
		
		[self leafInspectItem:item];
	}
	
	if (flag)
	{
		if (myTarget && myAction)
		{
			[myTarget performSelector:myAction withObject:self];
		}
	}
}

- (void)tableSelectedCell:(id)sender
{
	[self tableSelectedCell:sender notifyTarget:YES];
}

#pragma mark -
#pragma mark NSTableView Data Source

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	unsigned columnIndex = [self columnWithTable:aTableView];
	NSString *path = [self pathToColumn:columnIndex];
	
	id item = [myDataSource tableBrowser:self itemForPath:path];
	
	return [myDataSource tableBrowser:self numberOfChildrenOfItem:item];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	unsigned columnIndex = [self columnWithTable:aTableView];
	NSString *path = [self pathToColumn:columnIndex];
	id item = [myDataSource tableBrowser:self itemForPath:path];
	
	//NSLog(@"%@%@", NSStringFromSelector(_cmd), [item path]);
	
	return [myDataSource tableBrowser:self child:rowIndex ofItem:item];
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	
}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id <NSDraggingInfo>)info row:(int)row dropOperation:(NSTableViewDropOperation)operation
{
	return NO;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)operation
{
	return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
	return NO;
}

#pragma mark -
#pragma mark NSTableView Delegate

- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(int)rowIndex
{
	if (myFlags.isEnabled)
	{
		return YES;
	}
	
	return NO;
}

- (void)tableView:(NSTableView *)tableView didKeyPress:(NSString *)partialSearch
{
	// see if there is a cell that starts with the partial search string
	NSString *path = [self pathToColumn:[self columnWithTable:tableView]];
	id item = [myDataSource tableBrowser:self itemForPath:path];
	if (![item isDirectory])
	{
		item = [self parentOfItem:item];
	}
	NSCell *cell = [[[tableView tableColumns] objectAtIndex:0] dataCell];
	
	unsigned i, c = [myDataSource tableBrowser:self numberOfChildrenOfItem:item];
	id matchItem;
	
	for (i = 0; i < c; i++)
	{
		matchItem = [myDataSource tableBrowser:self child:i ofItem:item];
		[cell setObjectValue:matchItem];
		
		if ([[cell stringValue] hasPrefix:partialSearch])
		{
			// select the cell
			[tableView selectRow:i byExtendingSelection:NO];
			[tableView scrollRowToVisible:i];
			[self tableSelectedCell:tableView];
			break;
		}
	}
}

- (NSMenu *)tableView:(NSTableView *)tableView contextMenuForItem:(id)item
{
	if (myDelegateFlags.contextMenuWithItem)
	{
		return [myDelegate tableBrowser:self contextMenuWithItem:item];
	}
	
	return nil;
}

- (void)tableViewNavigateForward:(NSTableView *)tableView
{
	unsigned column = [self columnWithTable:tableView];
	NSString *path = [self pathToColumn:column + 1];
	id item = [myDataSource tableBrowser:self itemForPath:path];
	
	if ([item isDirectory])
	{
		if (column < [myColumns count] - 1)
		{
			NSTableView *next = [myColumns objectAtIndex:column + 1];
			
			if ([myDataSource tableBrowser:self numberOfChildrenOfItem:item] > 0)
			{
				[[self window] makeFirstResponder:next];
				[next selectRow:0 byExtendingSelection:NO];
				if ([next target] && [next action])
				{
					[[next target] performSelector:[next action] withObject:next];
				}
			}
		}
	}
}

- (void)tableViewNavigateBackward:(NSTableView *)tableView
{
	unsigned column = [self columnWithTable:tableView];
	if (column > 0)
	{
		NSTableView *previous = [myColumns objectAtIndex:column - 1];
		[[self window] makeFirstResponder:previous];
		
		if ([previous target] && [previous action])
		{
			[[previous target] performSelector:[previous action] withObject:previous];
		}
		
		[self scrollRectToVisible:[[previous enclosingScrollView] frame]];
	}
}

#pragma mark -
#pragma mark Resizer Delegate

- (void)resizer:(CKResizingButton *)resizer ofScrollView:(CKTableBrowserScrollView *)scrollView  movedBy:(float)xDelta affectsAllColumns:(BOOL)flag;
{
	unsigned column = [self columnWithTable:[scrollView documentView]];
	NSScrollView *scroller = nil;
	
	if (column != NSNotFound)
	{
		scroller = [[myColumns objectAtIndex:column] enclosingScrollView];
	}
	else
	{
		// this is the scroller of the leaf view
		scroller = [myLeafView enclosingScrollView];
	}
	
	
	if (flag)
	{
		// remove all custom sizes
		[myColumnWidths removeAllObjects];
		// set new default
		myDefaultColumnWidth = NSWidth([scroller frame]) + xDelta;
	}
	
	// set custom
	[myColumnWidths setObject:[NSNumber numberWithFloat:NSWidth([scroller frame]) + xDelta] forKey:[NSNumber numberWithUnsignedInt:column]];
	
	// if resizing all, first set all columns to be the same size
//	if (flag)
//	{
//		NSRect initialFrame = [scroller frame];
//		float initialWidth = NSWidth(initialFrame);
//		
//		unsigned i, c = [myColumns count];
//		NSScroller *cur;
//		NSRect iFrame, lastIFrame;
//		
//		cur = [myColumns objectAtIndex:0];
//		iFrame = [cur frame];
//		iFrame.size.width = initialWidth;
//		[cur setFrame:iFrame];
//		lastIFrame = iFrame;
//		
//		for (i = 1; i < c; i++)
//		{
//			cur = [myColumns objectAtIndex:i];
//			iFrame = [cur frame];
//			initialFrame.origin.x += (NSWidth(iFrame) - initialWidth);
//			iFrame.origin.x = NSMaxX(lastIFrame) + 1;
//			iFrame.size.width = initialWidth;
//			[cur setFrame:iFrame];
//		}
//	}
	
	NSRect frame = [scroller frame];
	frame.size.width += xDelta;
	// apply constraints
	if (NSWidth(frame) < myMinColumnWidth)
	{
		frame.size.width = myMinColumnWidth;
	}
	if ([scroller documentView] == myLeafView)
	{
		if (NSWidth(frame) < NSWidth([myLeafView frame]) + SCROLLER_WIDTH)
		{
			frame.size.width = NSWidth([myLeafView frame]) + SCROLLER_WIDTH;
		}
	}
	if (myMaxColumnWidth > 0 && NSWidth(frame) > myMaxColumnWidth)
	{
		frame.size.width = myMaxColumnWidth;
	}
	[scroller setFrame:frame];
	NSRect lastFrame = frame;
	
	// adjust views to the right
	for ( column++; column < [myColumns count]; column++)
	{
		NSScrollView *scroller = [[myColumns objectAtIndex:column] enclosingScrollView];
		frame = [scroller frame];
		frame.origin.x = NSMaxX(lastFrame) + 1;
		if (flag)
		{
			frame.size.width += xDelta;
			// apply constraints
			if (NSWidth(frame) < myMinColumnWidth)
			{
				frame.size.width = myMinColumnWidth;
			}
			if (myMaxColumnWidth > 0 && NSWidth(frame) > myMaxColumnWidth)
			{
				frame.size.width = myMaxColumnWidth;
			}
		}
		
		[scroller setFrame:frame];
		lastFrame = frame;
	}
	
	frame = [myLeafView frame];
	frame.origin.x = NSMaxX(lastFrame) + 1;
	[myLeafView setFrame:frame];
	
	[self setNeedsDisplay:YES];
	[self updateScrollers];
}

@end

static NSImage *sResizeImage = nil;

@interface CKResizingButton : NSView
{
	id myDelegate;
}

- (void)setDelegate:(id)delegate;

@end

@interface NSObject (CKResizingButtonDelegate)

- (void)resizer:(CKResizingButton *)resizer ofScrollView:(CKTableBrowserScrollView *)scrollView  movedBy:(float)xDelta affectsAllColumns:(BOOL)flag;

@end

@implementation CKResizingButton

- (id)initWithFrame:(NSRect)frame
{
	if ((self != [super initWithFrame:frame]))
	{
		[self release];
		return nil;
	}
	
	if (!sResizeImage)
	{
		NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"browser_resizer" ofType:@"tiff"];
		sResizeImage = [[NSImage alloc] initWithContentsOfFile:path];
	}
	
	return self;
}

- (void)setDelegate:(id)delegate
{
	if (![delegate respondsToSelector:@selector(resizer:ofScrollView:movedBy:affectsAllColumns:)])
	{
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"delegate does not respond to resizer:movedBy:" userInfo:nil];
	}
	myDelegate = delegate;
}

- (void)drawRect:(NSRect)rect
{
	[sResizeImage drawInRect:rect
					fromRect:NSZeroRect
				   operation:NSCompositeSourceOver
					fraction:1.0];
}

- (void)mouseDown:(NSEvent *)theEvent
{
	NSPoint point = [theEvent locationInWindow]; 
	BOOL allCols = ((GetCurrentKeyModifiers() & (optionKey | rightOptionKey)) != 0) ? YES : NO;
		
	while (1)
	{
		theEvent = [[self window] nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)];
		NSPoint thisPoint = [theEvent locationInWindow]; 
		
		//if (NSPointInRect([[self superview] convertPoint:thisPoint fromView:nil], [self frame]))
		{
			[myDelegate resizer:self ofScrollView:(CKTableBrowserScrollView *)[self superview] movedBy:thisPoint.x - point.x affectsAllColumns:allCols];
		}
			
		point = thisPoint;
		
		if ([theEvent type] == NSLeftMouseUp) {
            break;
        }
	}
}

@end

#define RESIZER_KNOB_SIZE 15.0

@implementation CKTableBrowserScrollView

- (id)initWithFrame:(NSRect)frame
{
	if ((self != [super initWithFrame:frame]))
	{
		[self release];
		return nil;
	}
	
	myResizer = [[CKResizingButton alloc] initWithFrame:NSMakeRect(0, 0, RESIZER_KNOB_SIZE, RESIZER_KNOB_SIZE)];
	[self addSubview:myResizer];
	
	return self;
}

- (void)dealloc
{
	[myResizer release];
	[super dealloc];
}

- (CKResizingButton *)resizer
{
	return myResizer;
}

- (void)setCanResize:(BOOL)flag
{
	myFlags.canResize = flag;
	[self setNeedsDisplay:YES];
}

- (BOOL)canResize
{
	return myFlags.canResize;
}

- (void)drawRect:(NSRect)rect
{
	[super drawRect:rect];
	[myResizer setNeedsDisplay:YES];
}

- (void)tile
{
	[super tile];
	
	NSScroller *vert = [self verticalScroller];
	NSRect frame = [vert frame];
	frame.size.height -= RESIZER_KNOB_SIZE;
	
	[vert setFrame:frame];
	
	NSRect resizerRect = [myResizer frame];
	resizerRect.origin.x = NSMinX(frame);
	resizerRect.origin.y = NSMaxY(frame) ;
	resizerRect.size.width = RESIZER_KNOB_SIZE;
	resizerRect.size.height = RESIZER_KNOB_SIZE;
	
	[myResizer setFrame:resizerRect];
}

- (void)scrollWheel:(NSEvent *)theEvent
{
	BOOL isHorizontal = ((GetCurrentKeyModifiers() & (shiftKey | rightShiftKey)) != 0) ? YES : NO;
	
	if (isHorizontal)
	{
		// us -> CKTableBasedBrowser -> scrollview
		[[[self superview] enclosingScrollView] scrollWheel:theEvent];
	}
	else
	{
		[super scrollWheel:theEvent];
	}
}

@end

@implementation CKBrowserTableView

#define KEYPRESS_DELAY 0.25
#define ARROW_NAVIGATION_DELAY 0.1

- (void)dealloc
{
	[myQuickSearchString release];
	[super dealloc];
}

- (void)searchConcatenationEnded
{
	[myQuickSearchString deleteCharactersInRange:NSMakeRange(0, [myQuickSearchString length])];
}

- (void)delayedSelectionChange
{
	if ([self target] && [self action])
	{
		[[self target] performSelector:[self action] withObject:self];
	}
}

- (void)keyDown:(NSEvent *)theEvent
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(searchConcatenationEnded) object:nil];
	
	if ([[theEvent characters] characterAtIndex:0] == NSDeleteFunctionKey ||
		[[theEvent characters] characterAtIndex:0] == NSDeleteCharFunctionKey ||
		[[theEvent characters] characterAtIndex:0] == NSDeleteLineFunctionKey)
	{
		[self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
	}
	else if ([[theEvent characters] characterAtIndex:0] == NSLeftArrowFunctionKey)
	{
		if ([[self delegate] respondsToSelector:@selector(tableViewNavigateBackward:)])
		{
			[[self delegate] tableViewNavigateBackward:self];
		}
	}
	else if ([[theEvent characters] characterAtIndex:0] == NSRightArrowFunctionKey)
	{
		if ([[self delegate] respondsToSelector:@selector(tableViewNavigateForward:)])
		{
			[[self delegate] tableViewNavigateForward:self];
		}
	}
	// we are using a delayed selector approach here so if someone just holds their finger down on the arrows, it won't go and fetch every single directory
	else if ([[theEvent characters] characterAtIndex:0] == NSUpArrowFunctionKey)
	{
		if ([self selectedRow] > 0)
		{
			[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(delayedSelectionChange) object:nil];
			
			[self selectRow:[self selectedRow] - 1 byExtendingSelection:NO];
			[self scrollRowToVisible:[self selectedRow] - 1];
			
			[self performSelector:@selector(delayedSelectionChange) withObject:nil afterDelay:ARROW_NAVIGATION_DELAY inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
		}
	}
	else if ([[theEvent characters] characterAtIndex:0] == NSDownArrowFunctionKey)
	{
		if ([self selectedRow] < [[self dataSource] numberOfRowsInTableView:self] - 1)
		{
			[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(delayedSelectionChange) object:nil];
			
			[self selectRow:[self selectedRow] + 1 byExtendingSelection:NO];
			[self scrollRowToVisible:[self selectedRow] + 1];
			
			[self performSelector:@selector(delayedSelectionChange) withObject:nil afterDelay:ARROW_NAVIGATION_DELAY inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
		}
	}
	else
	{
		if (!myQuickSearchString)
		{
			myQuickSearchString = [[NSMutableString alloc] initWithString:@""];
		}
		[myQuickSearchString appendString:[theEvent characters]];
		// send the string as it gets built up
		if ([[self delegate] respondsToSelector:@selector(tableView:didKeyPress:)])
		{
			[[self delegate] tableView:self didKeyPress:myQuickSearchString];
		}
		[self performSelector:@selector(searchConcatenationEnded) withObject:nil afterDelay:KEYPRESS_DELAY inModes:[NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
	}
}

- (void)deleteBackward:(id)sender
{
	if ([[self delegate] respondsToSelector:@selector(tableView:deleteRows:)])
	{
		[[self delegate] tableView:self deleteRows:[[self selectedRowEnumerator] allObjects]];
	}
}

- (void)deleteForward:(id)sender
{
	if ([[self delegate] respondsToSelector:@selector(tableView:deleteRows:)])
	{
		[[self delegate] tableView:self deleteRows:[[self selectedRowEnumerator] allObjects]];
	}
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
	if ([[self delegate] respondsToSelector:@selector(tableView:contextMenuForItem:)])
	{
		int row = [self rowAtPoint:[self convertPoint:[theEvent locationInWindow] fromView:nil]];
		id item = nil;
		
		if (row != NSNotFound)
		{
			item = [[self dataSource] tableView:self objectValueForTableColumn:[[self tableColumns] objectAtIndex:0] row:row];
		}
		return [[self delegate] tableView:self contextMenuForItem:item];
	}
	return nil;
}

- (void)scrollWheel:(NSEvent *)theEvent
{
	BOOL isHorizontal = ((GetCurrentKeyModifiers() & (shiftKey | rightShiftKey)) != 0) ? YES : NO;
	
	if (isHorizontal)
	{
		// us -> scrollview -> CKTableBasedBrowser -> scrollview
		[[[[self enclosingScrollView] superview] enclosingScrollView] scrollWheel:theEvent];
	}
	else
	{
		[super scrollWheel:theEvent];
	}
}

@end