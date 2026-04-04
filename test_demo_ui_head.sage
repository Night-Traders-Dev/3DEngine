# demo_ui.sage - Forge Engine Phase 6 Demo
# Full HUD: health bar, crosshair, score, info panel, minimap, pause menu
#
# Run: ./run.sh examples/demo_ui.sage
# Controls:
#   WASD=Move  Mouse=Look  ESC=Capture/Pause  SPACE=Jump
#   E=Shoot  R=Spawn AI  F=Fog  Q=Quit

import gpu
import math
import sys
from renderer import create_renderer, begin_frame, end_frame
from renderer import shutdown_renderer, check_resize, update_title_fps
from ecs import create_world, spawn, add_component, get_component
from ecs import has_component, query, register_system, tick_systems
from ecs import flush_dead, destroy, add_tag, query_tag, entity_count
from components import TransformComponent, NameComponent
from input import create_input, update_input, bind_action
from input import action_held, action_just_pressed
from input import mouse_delta, default_fps_bindings
