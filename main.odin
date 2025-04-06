package main

import json "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import rl "vendor:raylib"

SCREEN_WIDTH :: 640
SCREEN_HEIGHT :: 480

GAME_WIDTH :: 320
GAME_HEIGHT :: 240

TILE_SIZE :: 16

PLAYER_MOVE_SPEED :: 50
PLAYER_HEALTH :: 5

MainState :: enum {
	PAUSED,
	MAINMENU,
	GAMEOVER,
	LEVEL0,
	LEVEL1,
	LEVEL2,
	LEVEL3,
	LEVEL4,
}

PlayerAnimationState :: enum {
	IDLE,
	RUNNING_W,
	RUNNING_S,
	RUNNING_A,
	RUNNING_D,
	DEACTIVE,
	ACTIVE,
}

TileType :: enum {
	WALL,
	GROUND,
	SURGROUND,
	PROPS,
}

EntityType :: enum {
	PLAYER,
	MONSTER,
	ROPE,
	FIREPIT,
}

AnimationPlayer :: struct {
	state:          PlayerAnimationState,
	frame:          int,
	timer:          f32,
	frame_count:    int,
	frame_duration: f32,
}

Entity :: struct {
	position:        rl.Vector2,
	animationPlayer: ^AnimationPlayer,
	texture_id:      rl.Texture2D,
	type:            EntityType,

	//players
	movedir:         rl.Vector2,
	health:          int,

	//rope
	pickable:        bool,
	already_picked:  bool,

	//fire
	fire_active:     bool,
}

TileSet :: struct {
	first_gid: int,
	texture:   rl.Texture2D,
	tileType:  TileType,
}

LevelData :: struct {
	level_id:                  int,
	player_start_position:     rl.Vector2,
	lift_trigger_pos:          rl.Vector2,
	lift_trigger_dimentions:   rl.Vector2,
	//pickable ropes	
	rope_count_exists:         int,
	current_picked_rope_count: int,
	//
	locked:                    bool,
	won:                       bool,
}

State :: struct {
	current_state:            MainState,
	player:                   Entity,
	map_json:                 TiledMap,
	tilesets:                 []TileSet,
	map_width:                int,
	map_height:               int,
	tile_width:               int,
	tile_height:              int,
	tile_data:                []int,
	prop_data:                []int,
	camera:                   rl.Camera2D,
	render_texture:           rl.RenderTexture2D,
	fullscreen:               bool,
	levels:                   [5]LevelData,
	last_level:               int,
	//FONT
	main_font:                rl.Font,
	//SOUND
	sounds:                   map[string]rl.Sound,
	music:                    map[string]rl.Music,
	master_volume:            f32,
	is_muted:                 bool,
	audio_device_initialized: bool,
	//enemies+firepit+rope
	texture_efr:              rl.Texture2D,
	enemies:                  [dynamic]Entity,
	ropes:                    [dynamic]Entity,
	firepits:                 [dynamic]Entity,
}

TiledLayerObjectProperties :: struct {
	name:  string,
	type:  string,
	value: int,
}

TiledLayerObjects :: struct {
	id:         int,
	height:     f32,
	width:      f32,
	name:       string,
	properties: []TiledLayerObjectProperties,
	rotation:   int,
	x:          f32,
	y:          f32,
}

TiledLayerTile :: struct {
	id:      int,
	name:    string,
	type:    string, // should be "tilelayer"
	data:    []int,
	width:   int,
	height:  int,
	x:       int,
	y:       int,
	opacity: f32,
	visible: bool,
	objects: []TiledLayerObjects,
}

TiledMap :: struct {
	compressionlevel: int,
	height:           int,
	width:            int,
	tilewidth:        int,
	tileheight:       int,
	infinite:         bool,
	nextlayerid:      int,
	nextobjectid:     int,
	orientation:      string,
	renderorder:      string,
	tiledversion:     string,
	type:             string,
	version:          string,
	layers:           []TiledLayerTile, // you can also use []TiledLayer* if manually decoded
}

state: State

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "ld57")
	defer rl.CloseWindow()

	state.render_texture = rl.LoadRenderTexture(GAME_WIDTH, GAME_HEIGHT)
	defer rl.UnloadRenderTexture(state.render_texture)
	// Set window state
	state.fullscreen = false
	rl.SetWindowState({.WINDOW_RESIZABLE})

	init_game()
	rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		handle_input()
		update_game()
		draw_game()
	}
}


handle_input :: proc() {
	dt := rl.GetFrameTime()

	// Toggle fullscreen with F11 (available in all states)
	if rl.IsKeyPressed(.F11) {
		state.fullscreen = !state.fullscreen
		if state.fullscreen {
			monitor := rl.GetCurrentMonitor()
			rl.SetWindowSize(rl.GetMonitorWidth(monitor), rl.GetMonitorHeight(monitor))
			rl.ToggleFullscreen()
		} else {
			rl.ToggleFullscreen()
			rl.SetWindowSize(SCREEN_WIDTH, SCREEN_HEIGHT)
		}
	}

	switch state.current_state {
	case .MAINMENU:
		if rl.IsKeyPressed(.SPACE) {
			change_level(1) // Start from level 0
		}

	case .LEVEL0, .LEVEL1, .LEVEL2, .LEVEL3, .LEVEL4:
		// Player movement controls
		new_pos := state.player.position

		if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) {
			new_pos.y -= PLAYER_MOVE_SPEED * dt
			state.player.animationPlayer.state = .RUNNING_W
		} else if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) {
			new_pos.y += PLAYER_MOVE_SPEED * dt
			state.player.animationPlayer.state = .RUNNING_S
		} else if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) {
			new_pos.x += PLAYER_MOVE_SPEED * dt
			state.player.animationPlayer.state = .RUNNING_D
		} else if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) {
			new_pos.x -= PLAYER_MOVE_SPEED * dt
			state.player.animationPlayer.state = .RUNNING_A
		} else {
			state.player.animationPlayer.state = .IDLE
		}

		// Only update position if new position is not blocked
		if !is_tile_blocking(new_pos) {
			state.player.position = new_pos
			// Update movedir only if movement was successful
			state.player.movedir = {
				new_pos.x - state.player.position.x,
				new_pos.y - state.player.position.y,
			}
		}

		// Pause game
		if rl.IsKeyPressed(.P) {
			state.current_state = .PAUSED
		}

	case .PAUSED:
		if rl.IsKeyPressed(.P) || rl.IsKeyPressed(.SPACE) {
			if state.last_level >= 0 && state.last_level < 5 {
				state.current_state = MainState(int(MainState.LEVEL0) + state.last_level)

			}
		}
		if rl.IsKeyPressed(.M) {
			state.current_state = .MAINMENU
		}

	case .GAMEOVER:
		if rl.IsKeyPressed(.SPACE) {
			// Restart game
			change_level(0)
		}
		if rl.IsKeyPressed(.M) {
			state.current_state = .MAINMENU
		}
	}
}

update_game :: proc() {
	if state.current_state == .PAUSED ||
	   state.current_state == .MAINMENU ||
	   state.current_state == .GAMEOVER {
		return // Don't update game logic in these states
	}

	// Update camera to follow player
	state.camera.target = state.player.position
	state.camera.offset = {GAME_WIDTH / 2, GAME_HEIGHT / 2}

	// Keep camera within map bounds
	max_x := f32(state.map_width * state.tile_width) - GAME_WIDTH / 2
	max_y := f32(state.map_height * state.tile_height) - GAME_HEIGHT / 2

	state.camera.target.x = math.clamp(state.camera.target.x, GAME_WIDTH / 2, max_x)
	state.camera.target.y = math.clamp(state.camera.target.y, GAME_HEIGHT / 2, max_y)
}

init_game :: proc() {
	state.current_state = .MAINMENU

	state.camera = rl.Camera2D {
		zoom     = 1.0,
		rotation = 0.0,
		offset   = {GAME_WIDTH / 2, GAME_HEIGHT / 2},
		target   = {0, 0},
	}

	// Initialize player position
	state.player.type = .PLAYER
	state.player.position = {100, 100}
	state.player.texture_id = rl.LoadTexture("assets/elf.png")
	state.player.animationPlayer = new(AnimationPlayer)
	state.player.animationPlayer.frame = 0
	state.player.animationPlayer.timer = 0
	state.player.animationPlayer.frame_count = 4
	state.player.animationPlayer.frame_duration = 0.1
	state.player.animationPlayer.state = .IDLE
	state.player.health = PLAYER_HEALTH

	state.texture_efr = rl.LoadTexture("assets/fire-enemy-rope.png")

	enemy_animation_player := new(AnimationPlayer)
	enemy_animation_player.state = .IDLE
	enemy_animation_player.frame = 0
	enemy_animation_player.timer = 0
	enemy_animation_player.frame_count = 3
	enemy_animation_player.frame_duration = 0.1
	firepit_animation_player := new(AnimationPlayer)
	firepit_animation_player.state = .DEACTIVE
	firepit_animation_player.frame = 0
	firepit_animation_player.timer = 0
	firepit_animation_player.frame_count = 4
	firepit_animation_player.frame_duration = 0.1

	if parsed_json, ok := os.read_entire_file("assets/map.json", context.temp_allocator); ok {
		// if err := json.unmarshal(parsed_json, &state.map_json); err != nil {
		// 	fmt.eprintln("Failed to unmarshal JSON:", err)
		// 	os.exit(1) // Exit with error code
		// }

		if json.unmarshal(parsed_json, &state.map_json) == nil {

			state.tile_width = state.map_json.tilewidth
			state.tile_height = state.map_json.tileheight
			state.map_width = state.map_json.width
			state.map_height = state.map_json.height

			for layer in state.map_json.layers {
				if layer.id == 1 {
					state.tile_data = layer.data
				} else if layer.id == 5 {
					state.prop_data = layer.data
				}
			}

			walls_texture := rl.LoadTexture("assets/walls.png")
			grounds_texture := rl.LoadTexture("assets/grounds.png")
			surgrounds_texture := rl.LoadTexture("assets/surground.png")
			props_texture := rl.LoadTexture("assets/props.png")
			state.tilesets = make([]TileSet, 4, context.allocator)
			state.tilesets[0] = TileSet {
				first_gid = 1,
				texture   = walls_texture,
				tileType  = .WALL,
			}
			state.tilesets[1] = TileSet {
				first_gid = 225,
				texture   = grounds_texture,
				tileType  = .GROUND,
			}
			state.tilesets[2] = TileSet {
				first_gid = 433,
				texture   = surgrounds_texture,
				tileType  = .SURGROUND,
			}
			state.tilesets[3] = TileSet {
				first_gid = 615,
				texture   = props_texture,
				tileType  = .PROPS,
			}
		} else {
			fmt.println("Failed to unmarshal JSON")
		}

	} else {
		fmt.println("Failed to read my_struct_file")
	}
	//map user position for different levels
	for layer in state.map_json.layers {
		switch layer.name {
		case "playerstart":
			for obj in layer.objects {
				if obj.properties != nil && len(obj.properties) > 0 {
					level_id := obj.properties[0].value
					if level_id >= 0 && level_id < len(state.levels) {
						state.levels[level_id].player_start_position = {obj.x, obj.y}
						state.levels[level_id].level_id = level_id
					}
				}
			}

		case "lift":
			for obj in layer.objects {
				if obj.properties != nil && len(obj.properties) > 0 {
					level_id := obj.properties[0].value
					if level_id >= 0 && level_id < len(state.levels) {
						state.levels[level_id].lift_trigger_pos = {obj.x, obj.y}
						state.levels[level_id].lift_trigger_dimentions = {
							f32(obj.width),
							f32(obj.height),
						}
					}
				}
			}
		case "rope":
			for obj in layer.objects {
				if obj.properties != nil && len(obj.properties) > 0 {
					level_id := obj.properties[0].value
					if level_id >= 0 && level_id < len(state.levels) {
						state.levels[level_id].rope_count_exists += 1
						rope := Entity {
							position       = {obj.x, obj.y},
							type           = .ROPE,
							pickable       = true,
							already_picked = false,
							texture_id     = state.texture_efr, // Your rope texture
						}
						append(&state.ropes, rope)
					}
				}
			}
		case "enemy":
			for obj in layer.objects {
				if obj.properties != nil && len(obj.properties) > 0 {
					level_id := obj.properties[0].value
					if level_id >= 0 && level_id < len(state.levels) {
						enemy := Entity {
							position        = {obj.x, obj.y},
							type            = .MONSTER,
							texture_id      = state.texture_efr, // Your rope texture
							movedir         = {1, 0},
							animationPlayer = enemy_animation_player,
						}
						append(&state.enemies, enemy)
					}
				}
			}
		case "firepit":
			for obj in layer.objects {
				if obj.properties != nil && len(obj.properties) > 0 {
					level_id := obj.properties[0].value
					if level_id >= 0 && level_id < len(state.levels) {
						firepit := Entity {
							position        = {obj.x, obj.y},
							type            = .FIREPIT,
							texture_id      = state.texture_efr,
							fire_active     = false,
							animationPlayer = firepit_animation_player,
						}
						append(&state.firepits, firepit)
					}
				}
			}
		}
	}

	//sounds

	//enemies

}

draw_game :: proc() {
	// Draw to our render texture (game resolution)
	rl.BeginTextureMode(state.render_texture)
	{
		rl.ClearBackground(rl.BLACK)
		if state.current_state >= .LEVEL0 && state.current_state <= .LEVEL4 {
			rl.BeginMode2D(state.camera)
			{
				// Draw map tiles
				for y in 0 ..< state.map_height {
					for x in 0 ..< state.map_width {
						idx := y * state.map_width + x
						gid := state.tile_data[idx]
						if gid == 0 {
							continue
						}

						// Find the appropriate tileset
						tileset: ^TileSet = nil
						best_gid := -1
						for &ts in state.tilesets {
							if ts.first_gid <= gid && ts.first_gid > best_gid {
								tileset = &ts
								best_gid = ts.first_gid
							}
						}

						if tileset == nil {
							continue
						}

						local_id := gid - tileset.first_gid
						tileset_columns := int(tileset.texture.width) / state.tile_width
						tileset_rows := int(tileset.texture.height) / state.tile_height

						if local_id < 0 || local_id >= tileset_columns * tileset_rows {
							continue
						}

						src := rl.Rectangle {
							f32((local_id % tileset_columns) * state.tile_width),
							f32((local_id / tileset_columns) * state.tile_height),
							f32(state.tile_width),
							f32(state.tile_height),
						}
						dest := rl.Vector2{f32(x * state.tile_width), f32(y * state.tile_height)}

						rl.DrawTextureRec(tileset.texture, src, dest, rl.WHITE)
					}
				}
				//props tile layer
				for y in 0 ..< state.map_height {
					for x in 0 ..< state.map_width {
						idx := y * state.map_width + x
						gid := state.prop_data[idx]
						if gid == 0 {
							continue
						}

						// Find the appropriate tileset
						tileset: ^TileSet = nil
						best_gid := -1
						for &ts in state.tilesets {
							if ts.first_gid <= gid && ts.first_gid > best_gid {
								tileset = &ts
								best_gid = ts.first_gid
							}
						}

						if tileset == nil {
							continue
						}

						local_id := gid - tileset.first_gid
						tileset_columns := int(tileset.texture.width) / state.tile_width
						tileset_rows := int(tileset.texture.height) / state.tile_height

						if local_id < 0 || local_id >= tileset_columns * tileset_rows {
							continue
						}

						src := rl.Rectangle {
							f32((local_id % tileset_columns) * state.tile_width),
							f32((local_id / tileset_columns) * state.tile_height),
							f32(state.tile_width),
							f32(state.tile_height),
						}
						dest := rl.Vector2{f32(x * state.tile_width), f32(y * state.tile_height)}

						rl.DrawTextureRec(tileset.texture, src, dest, rl.WHITE)
					}
				}
				{
					anim := state.player.animationPlayer

					// Update animation timer
					anim.timer += rl.GetFrameTime()
					if anim.timer >= anim.frame_duration {
						anim.timer = 0
						anim.frame = (anim.frame + 1) % anim.frame_count
					}

					// Calculate frame position in sprite sheet
					frame_x := f32(anim.frame * TILE_SIZE)
					frame_y: f32 = 0 // Default row for IDLE

					// Select animation row based on state
					#partial switch anim.state {
					case .RUNNING_W:
						anim.frame_count = 4
						frame_y = f32(2 * TILE_SIZE)
					case .RUNNING_S:
						anim.frame_count = 4
						frame_y = f32(2 * TILE_SIZE)
					case .RUNNING_A:
						anim.frame_count = 4
						frame_y = f32(3 * TILE_SIZE)
					case .RUNNING_D:
						anim.frame_count = 4
						frame_y = f32(2 * TILE_SIZE)
					case .IDLE:
						anim.frame_count = 3
						frame_y = 0
					}

					player_src := rl.Rectangle{frame_x, frame_y, f32(TILE_SIZE), f32(TILE_SIZE)}

					player_pixel_pos := rl.Vector2 {
						state.player.position.x,
						state.player.position.y,
					}

					rl.DrawTextureRec(
						state.player.texture_id,
						player_src,
						player_pixel_pos,
						rl.WHITE,
					)
				}
				// In draw_game() after BeginMode2D()
				if ODIN_DEBUG {
					// Draw player collision box
					rl.DrawRectangleLinesEx(
						rl.Rectangle {
							state.player.position.x + 3,
							state.player.position.y + 3,
							f32(state.tile_width - 6),
							f32(state.tile_height - 6),
						},
						1,
						rl.RED,
					)

					// Draw blocking tiles
					for y in 0 ..< state.map_height {
						for x in 0 ..< state.map_width {
							idx := y * state.map_width + x
							gid := state.tile_data[idx]
							gid2 := state.prop_data[idx]
							if gid <= 225 || (gid2 > 615) {
								rl.DrawRectangleLines(
									i32(x * state.tile_width),
									i32(y * state.tile_height),
									i32(state.tile_width),
									i32(state.tile_height),
									rl.ColorAlpha(rl.RED, 0.5),
								)
							}
						}
					}
				}

			}
			rl.EndMode2D()
		}
		// Draw state-specific overlays
		#partial switch state.current_state {
		case .MAINMENU:
			draw_main_menu()
		case .PAUSED:
			draw_pause_menu()
		case .GAMEOVER:
			draw_game_over()
		}
	}
	rl.EndTextureMode()

	// Draw render texture to screen, scaled properly
	rl.BeginDrawing()
	{
		rl.ClearBackground(rl.BLACK)

		// Calculate scaling to maintain aspect ratio
		scale := min(
			f32(rl.GetScreenWidth()) / GAME_WIDTH,
			f32(rl.GetScreenHeight()) / GAME_HEIGHT,
		)

		dest_rect := rl.Rectangle {
			(f32(rl.GetScreenWidth()) - (GAME_WIDTH * scale)) * 0.5,
			(f32(rl.GetScreenHeight()) - (GAME_HEIGHT * scale)) * 0.5,
			GAME_WIDTH * scale,
			GAME_HEIGHT * scale,
		}

		rl.DrawTexturePro(
			state.render_texture.texture,
			rl.Rectangle{0, 0, GAME_WIDTH, -GAME_HEIGHT}, // Flip Y
			dest_rect,
			rl.Vector2{0, 0},
			0,
			rl.WHITE,
		)
	}
	rl.EndDrawing()
}

change_level :: proc(level: int) {
	if level == 0 {
		state.current_state = .LEVEL0
		state.player.position = state.levels[0].player_start_position
	} else if level == 1 {
		state.current_state = .LEVEL1
		state.player.position = state.levels[1].player_start_position
	} else if level == 2 {
		state.current_state = .LEVEL2
		state.player.position = state.levels[2].player_start_position
	} else if level == 3 {
		state.current_state = .LEVEL3
		state.player.position = state.levels[3].player_start_position
	} else if level == 4 {
		state.current_state = .LEVEL4
		state.player.position = state.levels[4].player_start_position
	}

	// Store last level for pause resume
	state.last_level = level
}
draw_main_menu :: proc() {
	rl.DrawText("MAIN MENU", GAME_WIDTH / 2 - 100, GAME_HEIGHT / 2 - 50, 40, rl.WHITE)
	rl.DrawText("Press SPACE to start", GAME_WIDTH / 2 - 120, GAME_HEIGHT / 2 + 20, 20, rl.WHITE)
}

draw_pause_menu :: proc() {
	rl.DrawRectangle(0, 0, GAME_WIDTH, GAME_HEIGHT, {0, 0, 0, 200}) // Semi-transparent overlay
	rl.DrawText("PAUSED", GAME_WIDTH / 2 - 80, GAME_HEIGHT / 2 - 40, 40, rl.WHITE)
	rl.DrawText("Press P to resume", GAME_WIDTH / 2 - 100, GAME_HEIGHT / 2 + 20, 20, rl.WHITE)
	rl.DrawText("Press M for main menu", GAME_WIDTH / 2 - 120, GAME_HEIGHT / 2 + 50, 20, rl.WHITE)
}
draw_game_over :: proc() {
	rl.DrawRectangle(0, 0, GAME_WIDTH, GAME_HEIGHT, {0, 0, 0, 200})
	rl.DrawText("GAME OVER", GAME_WIDTH / 2 - 100, GAME_HEIGHT / 2 - 40, 40, rl.RED)
	rl.DrawText("Press SPACE to restart", GAME_WIDTH / 2 - 120, GAME_HEIGHT / 2 + 20, 20, rl.WHITE)
	rl.DrawText("Press M for main menu", GAME_WIDTH / 2 - 120, GAME_HEIGHT / 2 + 50, 20, rl.WHITE)
}

is_tile_blocking :: proc(pos: rl.Vector2) -> bool {
	// Check all four corners of the player's hitbox
	points := []rl.Vector2 {
		{pos.x + 3, pos.y + 3}, // top-left
		{(pos.x + 3) + 10, (pos.y + 3)}, // top-right
		{(pos.x + 3), (pos.y + 3) + 10}, // bottom-left
		{(pos.x + 3) + 10, (pos.y + 3) + 10}, // bottom-right
	}


	for point in points {
		tile_x := int(point.x) / state.tile_width
		tile_y := int(point.y) / state.tile_height

		// Check bounds
		if tile_x < 0 || tile_x >= state.map_width || tile_y < 0 || tile_y >= state.map_height {
			return true
		}

		// Get tile data
		idx := tile_y * state.map_width + tile_x
		gid := state.tile_data[idx]
		gid2 := state.prop_data[idx]

		// Check if tile is blocking
		if gid <= 225 || (gid2 > 615) {
			return true
		}
	}
	return false
}
