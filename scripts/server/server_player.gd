extends Node3D
## The server's record of one connected player. Its position comes from the player's movement
## messages; zombies (M1.4) target it through the Sim like any other player record.

var player_name := ""
var peer_id := 0
var net_id := 0
var yaw := 0.0
var pitch := 0.0
var flags := 0
var dead := false
## Set when the player's game has loaded the world around it; only ready players count as online.
var is_ready := false
## Solo game: the pause menu is open (the world stops while every player has paused).
var paused := false
## The hotbar slot in the player's hand (from their movement), so others see what they hold.
var slot := 0
var admin := false
## Movement checking: the last accepted position and when it arrived, and the current move id
## (bumped on every server correction so in-flight moves from before it are ignored).
var last_good := Vector3.ZERO
## The last accepted position with solid ground under it: a backpack lands here after a fall
## out of the world.
var last_ground := Vector3.INF
var last_move_ms := 0
var move_id := 0
## Connection health, for the log: when anything last arrived, and ENet's ping and packet loss.
var last_recv_ms := 0
var ping_ms := 0
var loss_pct := 0.0
## Set when the server itself ends the session (kick, signed in elsewhere).
var leave_reason := ""
## Logged out but still in the world (M2): seconds until the character goes too.
var linger_left := 0.0
## The server's copy of the player's inventory (the account's), and whether to resend it.
var inv: Inventory = null
var inv_dirty := false
## Latest request seq handled; S_INV acknowledges it so the client can drop its guesses.
var last_seq := 0
var last_break_ms := 0
var last_hammer_ms := 0
## The storage box or bag this player has open (M4.2), or Vector3i.MIN.
var open_box := Vector3i.MIN
## Requests this session, and how many were refused (shown in the log when the player leaves).
var requests := 0
var refused := 0
var refuse_why := {}
## Chunk subscriptions (see Proto.SUB_RADIUS): keys this client is kept up to date on, the
## chunk they were computed around, and edited chunks still to send in full.
var subs := {}
var sub_center := Vector2i(1 << 30, 1 << 30)
var chunk_queue: Array = []
## Blocks to resend after a refused request, so the client's guess is undone.
var fixes: Array[Vector3i] = []


## Health and food live here online (the player's PC shows what S_STATS says).
var health := 100.0
var food := 100.0
var kills := 0
## Knockback makes a player move faster than walking; the movement check allows it until then.
var knock_until_ms := 0
var last_attack_ms := 0
## M4.3: the last arrow, bolt or spear this player sent flying (draw and reload times count from it).
var last_shot_ms := 0
var joined_ms := 0
## The numbers last sent in S_STATS (health, food, dead, kills), to send only changes.
var stats_sent: Array = []


## Zombies hit through this (it's a Sim player record), and so do falls.
func take_damage(amount: float, from: Vector3) -> void:
	if dead or not is_ready:
		return
	health -= amount
	if from != Vector3.ZERO:
		knock_until_ms = Time.get_ticks_msec() + 1000
	G.net_server.player_hurt(self, amount, from)
	if health <= 0.0:
		health = 0.0
		dead = true
		G.net_server.player_died(self)


## Kill rewards and drops go to whoever earned them.
func give(id: int, n: int) -> void:
	if inv.add(id, n) > 0:
		G.net_server.tell(self, "Inventory full!", Color(1, 0.5, 0.4))
	inv_dirty = true
