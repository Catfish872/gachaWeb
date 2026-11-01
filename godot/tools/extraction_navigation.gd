extends RefCounted
## Deterministic visible-map navigation. Never mutates gameplay state.
static func path(map: Dictionary, start: String, target: String, allow_boss: bool) -> Array:
 var queue: Array = [start]
 var previous: Dictionary = {start:""}
 while not queue.is_empty():
  var current: String = queue.pop_front()
  if current == target:
   var result: Array = []
   while current != start:
    result.push_front(current)
    current = previous[current]
   return result
  for edge in map.edges:
   var next := ""
   if edge[0] == current: next = str(edge[1])
   elif edge[1] == current: next = str(edge[0])
   if next.is_empty() or previous.has(next): continue
   if next == map.bossRoomId and not allow_boss: continue
   previous[next] = current
   queue.append(next)
 return []

static func next_room(x, policy: String, health := 1.0) -> String:
 var map: Dictionary = x.map_state()
 var current: String = map.currentRoomId
 var boss: String = map.bossRoomId
 var explored := int(map.explored)
 var target_count := 4 if policy == "shortest" else (7 if policy == "poi" else 11)
 if explored >= target_count and map.bossUnlocked:
  var boss_path := path(map,current,boss,true)
  if not boss_path.is_empty(): return boss_path[0]
 if policy == "shortest": return shortest_gate_step(map)
 var best := ""
 var best_score := -INF
 for room in map.rooms:
  if room.visited or room.type in ["entry","boss"]: continue
  var route := path(map,current,room.id,false)
  if route.is_empty(): continue
  var score := -float(route.size())
  if policy == "poi":
   var weight: float = {"vault":16.0,"shrine":14.0,"workshop":12.0,"cache":10.0,"hospital":9.0,"event":7.0,"rest":1.0,"battle":0.0,"elite":-1.0}.get(room.type,0.0)
   if health < 0.72 and room.type in ["hospital","rest"]: weight += 8.0
   score = weight / float(route.size())
  if score > best_score:
   best_score = score
   best = route[0]
 if best.is_empty() and map.bossUnlocked:
  var boss_path := path(map,current,boss,true)
  if not boss_path.is_empty(): best = boss_path[0]
 return best

static func bit_count(value: int) -> int:
 var count := 0
 while value:
  count += value & 1
  value >>= 1
 return count

static func shortest_gate_step(map: Dictionary) -> String:
 var indexes: Dictionary = {}
 var mask := 0
 var start := 0
 var boss := 0
 for i in range(map.rooms.size()):
  var room: Dictionary = map.rooms[i]
  indexes[room.id] = i
  if room.id == map.currentRoomId: start = i
  if room.id == map.bossRoomId: boss = i
  if room.visited and room.type not in ["entry","boss"]: mask |= 1 << i
 var queue: Array = [[start, mask, -1]]
 var seen: Dictionary = {mask * 16 + start:true}
 var cursor := 0
 while cursor < queue.size():
  var node: Array = queue[cursor]
  cursor += 1
  var current: int = node[0]
  for edge in map.edges:
   var next := -1
   if indexes[edge[0]] == current: next = indexes[edge[1]]
   elif indexes[edge[1]] == current: next = indexes[edge[0]]
   if next < 0: continue
   var next_mask: int = node[1]
   if next == boss and bit_count(next_mask) < int(map.requiredExploration): continue
   if map.rooms[next].type not in ["entry","boss"]: next_mask |= 1 << next
   var first: int = next if int(node[2]) < 0 else int(node[2])
   if next == boss: return map.rooms[first].id
   var key := next_mask * 16 + next
   if seen.has(key): continue
   seen[key] = true
   queue.append([next,next_mask,first])
 return ""
