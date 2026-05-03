package shapes

import hm "core:container/handle_map"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:slice"
import rl "vendor:raylib"

Vec2i :: [2]i32
Vec2f :: [2]f32

STARTING_WINDOW_WITDH :: 1000
STARTING_WINDOW_HEIGHT :: 1000
MAX_FPS :: 500

get_screen_centre :: proc() -> Vec2f {
	return {auto_cast rl.GetScreenWidth() / 2, auto_cast rl.GetScreenHeight() / 2}
}

Entity_User_Act_State :: enum {
	Set,
	Hovered,
	Dragged,
}
Shape :: enum {
	Rectangle,
	Circle,
}
Entity :: struct {
	handle:            Entity_Handle,
	width:             f32,
	height:            f32,
	radius:            f32,
	shape:             Shape,
	position:          Vec2f,
	z_depth:           f32,
	colour:            [4]u8,
	user_act_state:    Entity_User_Act_State,
	last_set_position: Vec2f,
	last_set_z_depth:  f32,
}

entity_save_set_state :: proc(entity: ^Entity) {
	entity.last_set_position = entity.position
	entity.last_set_z_depth = entity.z_depth
}

entity_restore_last_set_state :: proc(entity: ^Entity) {
	entity.position = entity.last_set_position
	entity.z_depth = entity.last_set_z_depth
}

Entity_Handle :: hm.Handle32
Handle_Map :: hm.Static_Handle_Map

MAX_ENTITIES :: 1024
Game :: struct {
	entities:               Handle_Map(1024, Entity, Entity_Handle),
	min_depth:              f32,
	hud_on:                 bool,
	entity_last_selected:   Entity_Handle,
	entity_on_mouse_cursor: Entity_Handle,
	camera:                 rl.Camera2D,
}
game: Game

game_setup :: proc(game: ^Game) {
	game.hud_on = true
	game.camera = {
		zoom   = 1,
		offset = get_screen_centre(),
	}
}

entity_get :: proc(handle: Entity_Handle) -> (^Entity, bool) {
	return hm.static_get(&game.entities, handle)
}

entity_add :: proc(entity: Entity) -> (Entity_Handle, bool) {
	draw_order_sort_required = true
	return hm.static_add(&game.entities, entity)
}

entity_remove :: proc(handle: Entity_Handle) -> bool {
	ok := hm.static_remove(&game.entities, handle)
	if ok {
		draw_order_sort_required = true
		return true
	} else {return false}
}

entity_create_random_shape :: proc(pos: Vec2f = {0, 0}) -> (Entity_Handle, bool) {
	w: f32
	h: f32
	r: f32
	s: Shape
	mid_pos := pos
	if rand.float32() < 0.5 {
		r = 80
		s = .Circle
	} else {
		w = 120
		h = 160
		s = .Rectangle
		mid_pos = pos - {w, h} / 2
	}
	c: [4]u8 = {
		u8(rand.uint_range(0, 256)),
		u8(rand.uint_range(0, 256)),
		u8(rand.uint_range(0, 256)),
		255,
	}
	game.min_depth -= 0.1
	return entity_add(
		{
			position = mid_pos,
			last_set_position = mid_pos,
			z_depth = game.min_depth,
			last_set_z_depth = game.min_depth,
			width = w,
			height = h,
			radius = r,
			shape = s,
			colour = c,
		},
	)
}

entity_map_fill_with_circles :: proc() {
	for idx in 0 ..< len(game.entities.items) {
		row, col := math.divmod(idx, 30)
		c: [4]u8 = {
			u8(rand.uint_range(0, 256)),
			u8(rand.uint_range(0, 256)),
			u8(rand.uint_range(0, 256)),
			255,
		}
		pos := rl.GetScreenToWorld2D({f32(50 + row * 25), f32(50 + col * 25)}, game.camera)
		game.min_depth -= 0.1
		entity_add(
			{
				position = pos,
				last_set_position = pos,
				radius = 16,
				z_depth = game.min_depth,
				last_set_z_depth = game.min_depth,
				colour = c,
				shape = .Circle,
			},
		)
	}
}


draw_order_sort_required: bool = true
draw_order_list: [dynamic; MAX_ENTITIES]Entity_Handle
draw_order_update :: proc() {
	if draw_order_sort_required {
		clear(&draw_order_list)
		it := hm.iterator_make(&game.entities)
		for entity, handle in hm.iterate(&it) {
			append(&draw_order_list, handle)
		}
		entity_draw_priority :: proc(i, j: Entity_Handle) -> bool {
			i, _ := entity_get(i)
			j, _ := entity_get(j)
			return j.z_depth < i.z_depth
		}
		slice.sort_by(draw_order_list[:], entity_draw_priority)
		draw_order_sort_required = false
	}
}

entity_draw_as_rectangle :: proc(e: ^Entity) {
	rectangle: rl.Rectangle = {e.position.x, e.position.y, e.width, e.height}
	rl.DrawRectangleRec(rectangle, rl.Color(e.colour))
	switch e.user_act_state {
	case .Hovered:
		{
			rl.DrawRectangleLinesEx(rectangle, 2, rl.WHITE)
		}
	case .Dragged:
		{
			rl.DrawRectangleLinesEx(rectangle, 2, rl.RED)
		}
	case .Set:
		{}
	}
}

entity_draw_as_circle :: proc(e: ^Entity) {
	rl.DrawCircleV(e.position, e.radius, rl.Color(e.colour))
	switch e.user_act_state {
	case .Hovered:
		{
			rl.DrawRing(e.position, e.radius, (e.radius + 2), 0, 360, 32, rl.WHITE)
		}
	case .Dragged:
		{
			rl.DrawRing(e.position, e.radius, (e.radius + 2), 0, 360, 32, rl.RED)
		}
	case .Set:
		{}
	}
}

entity_draw :: proc(handle: Entity_Handle) {
	if e, ok := entity_get(handle); ok {
		switch e.shape {
		case .Rectangle:
			{entity_draw_as_rectangle(e)}
		case .Circle:
			{entity_draw_as_circle(e)}
		}
	}
}

entity_draw_all :: proc() {
	draw_order_update()
	for handle in draw_order_list {
		entity_draw(handle)
	}
}

draw_entity_map_representation :: proc() {
	for &entity, idx in game.entities.items {
		col, row := math.divmod(idx, 128)
		col_count := len(game.entities.items) / 128
		box_x_pos := rl.GetScreenWidth() - i32(5 + 5 * (col_count - col))
		box_y_pos := 5 * (row + 1)
		colour: rl.Color
		if entity.handle.idx > 0 {
			if entity.handle.gen == 1 {
				colour = rl.GREEN
			} else {
				colour = rl.YELLOW
			}
		} else if entity.handle.idx == 0 {
			if entity.handle.gen > 0 {
				colour = rl.RED
			} else {
				colour = rl.GRAY
			}
		}
		rl.DrawRectangle(box_x_pos, auto_cast box_y_pos, 3, 3, colour)
	}
}

draw_hud :: proc() {
	if game.hud_on {
		rl.DrawRectangle(
			i32(get_screen_centre().x) - 2,
			i32(get_screen_centre().y) - 2,
			4,
			4,
			rl.RED,
		)
		font := rl.LoadFontEx("FiraCode-Medium.ttf", 20, nil, 0)
		rl.DrawFPS(0, 0)
		rl.DrawTextEx(font, "Right click:   Create/Destroy", {0, 19}, 20, 0.5, rl.WHITE)
		rl.DrawTextEx(font, "Left click:    Drag Around", {0, 39}, 20, 0.5, rl.WHITE)
		rl.DrawTextEx(font, "Middle click:  Pan Camera", {0, 59}, 20, 0.5, rl.WHITE)
		rl.DrawTextEx(font, "Scroll wheel:  Zoom Camera", {0, 79}, 20, 0.5, rl.WHITE)
		rl.DrawTextEx(font, "F11:           Windowed Fullscreen", {0, 99}, 20, 0.5, rl.WHITE)
		rl.DrawTextEx(font, "Tab:           Toggle HUD", {0, 119}, 20, 0.5, rl.WHITE)
		rl.DrawTextEx(font, "Delete:        Destroy All Shapes", {0, 139}, 20, 0.5, rl.WHITE)
		rl.DrawTextEx(font, "F9:            Create All Circles", {0, 159}, 20, 0.5, rl.WHITE)
		draw_entity_map_representation()
	}
}

entity_on_top_at_position :: proc(pos: Vec2f) -> (^Entity, bool) {
	draw_order_update()
	#reverse for handle in draw_order_list {
		if e, ok := entity_get(handle); ok {
			switch e.shape {
			case .Rectangle:
				if rl.CheckCollisionPointRec(
					pos,
					{e.position.x, e.position.y, e.width, e.height},
				) {return e, true}
			case .Circle:
				if rl.CheckCollisionPointCircle(pos, e.position, e.radius) {return e, true}
			}
		}
	}
	return nil, false
}

last_mouse_world_position: Vec2f
last_hovered_entity_handle: Entity_Handle
handle_input :: proc() {
	// These work anywhere
	if rl.IsKeyPressed(.DELETE) {
		hm.clear(&game.entities)
	}
	if rl.IsKeyPressed(.F9) {
		entity_map_fill_with_circles()
	}
	if rl.IsKeyPressed(.F11) {
		rl.ToggleBorderlessWindowed()
	}
	if rl.IsKeyPressed(.TAB) {
		game.hud_on = !game.hud_on
	}
	if rl.GetMouseWheelMove() == 1 && game.camera.zoom < 4 {
		game.camera.zoom *= 1.2
	}
	if rl.GetMouseWheelMove() == -1 && game.camera.zoom > 0.1 {
		game.camera.zoom /= 1.2
	}
	if rl.IsMouseButtonDown(.MIDDLE) {
		game.camera.target -= rl.GetMouseDelta() / game.camera.zoom
	}

	// These require mouse position context
	hovered_entity, hover_ok := entity_on_top_at_position(last_mouse_world_position)
	last_hovered_entity, last_hover_ok := entity_get(last_hovered_entity_handle)
	if hover_ok {
		if last_hover_ok && last_hovered_entity_handle != hovered_entity.handle {
			last_hovered_entity.user_act_state = .Set
		}
		last_hovered_entity_handle = hovered_entity.handle
		switch hovered_entity.user_act_state {
		case .Set:
			{
				entity_save_set_state(hovered_entity)
				hovered_entity.user_act_state = .Hovered
			}
		case .Hovered:
			{
				if rl.IsMouseButtonPressed(.LEFT) {
					hovered_entity.user_act_state = .Dragged
					game.min_depth -= 0.1
					hovered_entity.z_depth = game.min_depth
					draw_order_sort_required = true
				}
				if rl.IsMouseButtonPressed(.RIGHT) {
					entity_remove(hovered_entity.handle)
				}
			}
		case .Dragged:
			{
				hovered_entity.position += rl.GetMouseDelta() / game.camera.zoom
				if rl.IsMouseButtonPressed(.RIGHT) {
					entity_restore_last_set_state(hovered_entity)
					hovered_entity.user_act_state = .Set
					draw_order_sort_required = true
				}
				if rl.IsMouseButtonReleased(.LEFT) {
					entity_save_set_state(hovered_entity)
					hovered_entity.user_act_state = .Set
					draw_order_sort_required = true
				}
			}
		}
	} else {
		if last_hover_ok {last_hovered_entity.user_act_state = .Set}
		if rl.IsMouseButtonPressed(.RIGHT) {
			entity_create_random_shape(last_mouse_world_position)
		}
	}

	last_mouse_world_position = rl.GetScreenToWorld2D(rl.GetMousePosition(), game.camera)
}

raylib_setup :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT} | {.WINDOW_RESIZABLE})
	rl.InitWindow(STARTING_WINDOW_WITDH, STARTING_WINDOW_HEIGHT, "Shapes from Odin!")
	rl.SetTargetFPS(MAX_FPS)
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground({76, 53, 83, 255})
	rl.BeginMode2D(game.camera)
	rl.DrawRectangle(-10, -10, 20, 20, rl.WHITE)
	entity_draw_all()
	rl.EndMode2D()
	draw_hud()
	rl.EndDrawing()
}

main :: proc() {

	// tracking allocator
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocation(s) not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	// initial setup
	raylib_setup()
	game_setup(&game)

	// game loop
	for !rl.WindowShouldClose() {
		// forces centre of screen to remain the centre after a resize
		game.camera.offset = get_screen_centre()
		handle_input()
		draw()
	}
	rl.CloseWindow()
}
