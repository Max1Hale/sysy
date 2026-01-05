const std = @import("std");

pub const Panel = enum {
    cpu,
    memory,
    disk,
    network,
    processes,

    pub fn toInt(self: Panel) u8 {
        return @intFromEnum(self);
    }

    pub fn fromInt(value: u8) ?Panel {
        return switch (value) {
            0 => .cpu,
            1 => .memory,
            2 => .disk,
            3 => .network,
            4 => .processes,
            else => null,
        };
    }
};

pub const UIState = struct {
    active_panel: Panel,
    process_scroll_offset: usize,
    selected_process_index: usize,
    screen_width: usize,
    screen_height: usize,

    pub fn init() UIState {
        return UIState{
            .active_panel = .processes,
            .process_scroll_offset = 0,
            .selected_process_index = 0,
            .screen_width = 80,
            .screen_height = 24,
        };
    }

    pub fn setScreenSize(self: *UIState, width: usize, height: usize) void {
        self.screen_width = width;
        self.screen_height = height;
    }

    pub fn scrollDown(self: *UIState, max_items: usize) void {
        if (self.active_panel != .processes) return;

        if (self.selected_process_index + 1 < max_items) {
            self.selected_process_index += 1;

            // Scroll if needed (keep selection visible in bottom half)
            const visible_height = self.getProcessListHeight();
            if (visible_height > 0 and self.selected_process_index >= self.process_scroll_offset + visible_height) {
                self.process_scroll_offset = self.selected_process_index - visible_height + 1;
            }
        }
    }

    pub fn scrollUp(self: *UIState) void {
        if (self.active_panel != .processes) return;

        if (self.selected_process_index > 0) {
            self.selected_process_index -= 1;

            // Scroll if needed (keep selection visible in top half)
            if (self.selected_process_index < self.process_scroll_offset) {
                self.process_scroll_offset = self.selected_process_index;
            }
        }
    }

    pub fn pageDown(self: *UIState, max_items: usize) void {
        if (self.active_panel != .processes) return;

        const visible_height = self.getProcessListHeight();
        if (visible_height == 0) return;

        const new_index = @min(
            self.selected_process_index + visible_height,
            if (max_items > 0) max_items - 1 else 0,
        );
        self.selected_process_index = new_index;
        self.process_scroll_offset = if (new_index >= visible_height) new_index - visible_height + 1 else 0;
    }

    pub fn pageUp(self: *UIState) void {
        if (self.active_panel != .processes) return;

        const visible_height = self.getProcessListHeight();
        if (visible_height == 0) return;

        if (self.selected_process_index >= visible_height) {
            self.selected_process_index -= visible_height;
        } else {
            self.selected_process_index = 0;
        }
        self.process_scroll_offset = if (self.selected_process_index > 0) self.selected_process_index else 0;
    }

    pub fn switchToPanel(self: *UIState, panel: Panel) void {
        self.active_panel = panel;
    }

    fn getProcessListHeight(self: *const UIState) usize {
        // Estimate: screen height - header graphs section (about 12 lines) - status bar (1 line)
        if (self.screen_height > 15) {
            return self.screen_height - 15;
        }
        return 1;
    }
};
