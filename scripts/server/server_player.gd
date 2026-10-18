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
var admin := false
## Movement checking: the last accepted position and when it arrived, and the current move id
## (bumped on every server correction so in-flight moves from before it are ignored).
var last_good := Vector3.ZERO
var last_move_ms := 0
var move_id := 0
## Connection health, for the log: when anything last arrived, and ENet's ping and packet loss.
var last_recv_ms := 0
var ping_ms := 0
var loss_pct := 0.0
## Set when the server itself ends the session (kick, signed in elsewhere).
var leave_reason := ""
## The server's copy of the player's inventory (the account's), and whether to resend it.
var inv: Inventory = null
var inv_dirty := false
## Latest request seq handled; S_INV acknowledges it so the client can drop its guesses.
var last_seq := 0
var last_break_ms := 0
## Requests this session, and how many were refused (shown in the log when the player leaves).
var requests := 0
var refused := 0
## Chunk subscriptions (see Proto.SUB_RADIUS): keys this client is kept up to date on, the
## chunk they were computed around, and edited chunks still to send in full.
var subs := {}
var sub_center := Vector2i(1 << 30, 1 << 30)
var chunk_queue: Array = []
## Blocks to resend after a refused request, so the client's guess is undone.
var fixes: Array[Vector3i] = []


func take_damage(_amount: float, _from: Vector3) -> void:
	# Players' health lives on their own PC until M1.4 sends damage to them.
	pass
