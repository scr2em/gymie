// Generated from the pose server's exercise catalog (PoseServer/analysis/exercises.py + demos.py).
// The local pose engine sends its own copy when a break connects; this is the fallback.

enum BundledCatalog {
    static let json = #"""
[
 {
  "key": "neck_tilt",
  "label": "Neck side tilt",
  "category": "Neck tension",
  "camera": "front",
  "stance": "seated",
  "how_to": "Ear towards shoulder, back to centre, then the other side. Each side is a rep.",
  "demo_url": "https://www.youtube.com/watch?v=gBL3gYNtun0"
 },
 {
  "key": "head_turn",
  "label": "Look over your shoulder",
  "category": "Neck tension",
  "camera": "front",
  "stance": "seated",
  "how_to": "Turn your head slowly to one side, back to centre, then the other side.",
  "demo_url": "https://www.youtube.com/watch?v=TBjOVrkpBy0"
 },
 {
  "key": "chin_to_chest",
  "label": "Chin to chest",
  "category": "Neck tension",
  "camera": "front",
  "stance": "seated",
  "how_to": "Sit tall, slowly lower your chin towards your chest, then lift your head back up.",
  "demo_url": "https://www.youtube.com/watch?v=jpW6X3zffuM"
 },
 {
  "key": "shoulder_shrug",
  "label": "Shoulder shrugs",
  "category": "Neck tension",
  "camera": "front",
  "stance": "seated",
  "how_to": "Lift both shoulders up towards your ears, hold for a moment, then let them drop.",
  "demo_url": "https://www.youtube.com/watch?v=9tFavSFK7UY"
 },
 {
  "key": "chin_tuck",
  "label": "Chin tuck",
  "category": "Neck tension",
  "camera": "side",
  "stance": "seated",
  "how_to": "Sit tall, let your head glide forward, then pull your chin straight back into a double chin.",
  "demo_url": "https://www.youtube.com/watch?v=kUuU2augcxg"
 },
 {
  "key": "cross_swing",
  "label": "Arm open & cross",
  "category": "Rounded shoulders",
  "camera": "front",
  "stance": "seated",
  "how_to": "Open your arms wide, then hug them across your chest.",
  "demo_url": "https://www.youtube.com/watch?v=FBg8ilWkEK8"
 },
 {
  "key": "wy_raise",
  "label": "W to Y raise",
  "category": "Rounded shoulders",
  "camera": "front",
  "stance": "seated",
  "how_to": "Arms in a W with your shoulder blades squeezed, slide them up into a Y, then back to the W.",
  "demo_url": "https://www.youtube.com/watch?v=HBCE9Ek0jLw"
 },
 {
  "key": "shoulder_roll",
  "label": "Backward shoulder rolls",
  "category": "Rounded shoulders",
  "camera": "front",
  "stance": "seated",
  "how_to": "Roll both shoulders up towards your ears, back, and down. Each roll is a rep.",
  "demo_url": "https://www.youtube.com/watch?v=c-UmFZ8A_1Q"
 },
 {
  "key": "thoracic_extension",
  "label": "Chair-back extension",
  "category": "Rounded shoulders",
  "camera": "side",
  "stance": "seated",
  "how_to": "Hands behind your head, gently arch your upper back over the top of your chair, then sit tall.",
  "demo_url": "https://www.youtube.com/watch?v=qtFE6CHGK5Q"
 },
 {
  "key": "clasp_opener",
  "label": "Clasped-hands chest opener",
  "category": "Rounded shoulders",
  "camera": "side",
  "stance": "standing",
  "how_to": "Clasp your hands behind your back, squeeze your shoulder blades, lift your hands away, then lower.",
  "demo_url": "https://www.youtube.com/watch?v=kxvUpG69uUc"
 },
 {
  "key": "seated_row",
  "label": "Seated rows",
  "category": "Upper back",
  "camera": "side",
  "stance": "seated",
  "how_to": "Arms straight in front, pull the elbows back and squeeze the shoulder blades.",
  "demo_url": "https://www.youtube.com/watch?v=zw3fZKVS4tQ"
 },
 {
  "key": "t_raise",
  "label": "T-raise",
  "category": "Upper back",
  "camera": "front",
  "stance": "seated",
  "how_to": "Lift both arms out to the sides to shoulder height, squeeze your shoulder blades, then lower.",
  "demo_url": "https://www.youtube.com/watch?v=XPPfnSEATJA"
 },
 {
  "key": "desk_punch",
  "label": "Desk punches",
  "category": "Upper back",
  "camera": "side",
  "stance": "seated",
  "how_to": "Fists by your chest, punch straight forward, then pull back.",
  "demo_url": "https://www.youtube.com/watch?v=FyaEGllqGDc"
 },
 {
  "key": "rhomboid_stretch",
  "label": "Upper back stretch",
  "category": "Upper back",
  "camera": "side",
  "stance": "seated",
  "how_to": "Clasp your hands in front, push them forward and round your upper back, then sit tall.",
  "demo_url": "https://www.youtube.com/watch?v=IxAI_7vL-aw"
 },
 {
  "key": "desk_row",
  "label": "One-arm desk row",
  "category": "Upper back",
  "camera": "side",
  "stance": "standing",
  "how_to": "Lean on the desk with your far hand, pull the other elbow back to your ribs, then lower it.",
  "demo_url": "https://www.youtube.com/watch?v=gzDJWs1kTlQ"
 },
 {
  "key": "scaption",
  "label": "Scaption raise",
  "category": "Shoulder & rotator cuff",
  "camera": "front",
  "stance": "seated",
  "how_to": "Thumbs up, raise both straight arms slightly forward of your sides to shoulder height, then lower.",
  "demo_url": "https://www.youtube.com/watch?v=pPenE8MnVgU"
 },
 {
  "key": "front_raise",
  "label": "Front arm raise",
  "category": "Shoulder & rotator cuff",
  "camera": "side",
  "stance": "seated",
  "how_to": "Lift a straight arm forward to shoulder height, then lower it.",
  "demo_url": "https://www.youtube.com/watch?v=E-E0EqERFBg"
 },
 {
  "key": "overhead_reach",
  "label": "Overhead reach",
  "category": "Shoulder & rotator cuff",
  "camera": "front",
  "stance": "seated",
  "how_to": "Reach both arms up towards the ceiling, then lower them.",
  "demo_url": "https://www.youtube.com/watch?v=JLWVzoM9cxQ"
 },
 {
  "key": "external_rotation",
  "label": "Elbows-in outward rotation",
  "category": "Shoulder & rotator cuff",
  "camera": "front",
  "stance": "seated",
  "how_to": "Elbows tucked at your sides and bent, rotate both hands out wide, then back in front of you.",
  "demo_url": "https://www.youtube.com/watch?v=PzX0v9JQJVA"
 },
 {
  "key": "cross_body_stretch",
  "label": "Cross-body shoulder stretch",
  "category": "Shoulder & rotator cuff",
  "camera": "front",
  "stance": "seated",
  "how_to": "Bring one arm across your chest, hug it in with the other hand, release, then switch arms.",
  "demo_url": "https://www.youtube.com/watch?v=RcQM08F8xvI"
 },
 {
  "key": "seated_side_bend",
  "label": "Seated side bend",
  "category": "Lower back",
  "camera": "front",
  "stance": "seated",
  "how_to": "Sit tall, lean to one side, back to centre, then the other side.",
  "demo_url": "https://www.youtube.com/watch?v=G6MnSiYRYkU"
 },
 {
  "key": "knee_to_chest",
  "label": "Seated knee hug",
  "category": "Lower back",
  "camera": "side",
  "stance": "seated",
  "how_to": "Sit tall, hug one knee up towards your chest, lower it, then switch legs.",
  "demo_url": "https://www.youtube.com/watch?v=MwFslmc6k0U"
 },
 {
  "key": "hip_hinge",
  "label": "Hip hinge",
  "category": "Lower back",
  "camera": "side",
  "stance": "standing",
  "how_to": "Soft knees, push your hips back and tip your chest forward, then stand tall.",
  "demo_url": "https://www.youtube.com/watch?v=RNgwXYQ4F0s"
 },
 {
  "key": "standing_side_bend",
  "label": "Standing side bend",
  "category": "Lower back",
  "camera": "front",
  "stance": "standing",
  "how_to": "Stand tall, slide one hand down your leg, back to centre, then the other side.",
  "demo_url": "https://www.youtube.com/watch?v=8dAH_w94pDU"
 },
 {
  "key": "back_extension",
  "label": "Standing back extension",
  "category": "Lower back",
  "camera": "side",
  "stance": "standing",
  "how_to": "Stand tall with your hands on your lower back, gently lean back, then return.",
  "demo_url": "https://www.youtube.com/watch?v=IAMfLvZqAhs"
 },
 {
  "key": "wrist_flex",
  "label": "Wrist flex & extend",
  "category": "Wrist & hand",
  "camera": "side",
  "stance": "seated",
  "how_to": "Arm out in front, bend the hand up or down, then straighten it.",
  "demo_url": "https://www.youtube.com/watch?v=TjYzzl_RbbM"
 },
 {
  "key": "extensor_stretch",
  "label": "Wrist extensor stretch",
  "category": "Wrist & hand",
  "camera": "side",
  "stance": "seated",
  "how_to": "Arm straight out, palm down. Gently bend the hand down with your other hand, then release.",
  "demo_url": "https://www.youtube.com/watch?v=tySyj745A0A"
 },
 {
  "key": "flexor_stretch",
  "label": "Wrist flexor stretch",
  "category": "Wrist & hand",
  "camera": "side",
  "stance": "seated",
  "how_to": "Arm straight out, palm up. Gently pull your fingers back with your other hand, then release.",
  "demo_url": "https://www.youtube.com/watch?v=z_C50jktRbU"
 },
 {
  "key": "prayer_stretch",
  "label": "Prayer stretch",
  "category": "Wrist & hand",
  "camera": "front",
  "stance": "seated",
  "how_to": "Palms together in front of your chest, lower your hands until the wrists stretch, then lift them.",
  "demo_url": "https://www.youtube.com/watch?v=_x9CCeFtuZ4"
 },
 {
  "key": "nerve_glide",
  "label": "Median nerve glide",
  "category": "Wrist & hand",
  "camera": "front",
  "stance": "seated",
  "how_to": "Hands by your shoulders, palms up. Straighten both arms out to the sides, palms out, then bend back.",
  "demo_url": "https://www.youtube.com/watch?v=frl-Ca2aYV8"
 },
 {
  "key": "seated_knee_ext",
  "label": "Seated leg extension",
  "category": "Knees",
  "camera": "side",
  "stance": "seated",
  "how_to": "Sit tall, straighten one leg out in front, lower it, then switch.",
  "demo_url": "https://www.youtube.com/watch?v=grE0Gbhh7pg"
 },
 {
  "key": "heel_slide",
  "label": "Seated heel slide",
  "category": "Knees",
  "camera": "side",
  "stance": "seated",
  "how_to": "Feet flat, slide one foot back under your chair to bend the knee, slide it forward, then switch.",
  "demo_url": "https://www.youtube.com/watch?v=g-BVnc8mE9Y"
 },
 {
  "key": "sit_to_stand",
  "label": "Sit to stand",
  "category": "Knees",
  "camera": "side",
  "stance": "standing",
  "how_to": "Stand up from your chair and sit back down without using your hands.",
  "demo_url": "https://www.youtube.com/watch?v=Dg20pIkkzh8"
 },
 {
  "key": "mini_squat",
  "label": "Mini squat",
  "category": "Knees",
  "camera": "side",
  "stance": "standing",
  "how_to": "Hold the desk if you like and bend the knees a little, then stand tall.",
  "demo_url": "https://www.youtube.com/watch?v=NDdzXVxrh-U"
 },
 {
  "key": "hamstring_curl",
  "label": "Standing hamstring curl",
  "category": "Knees",
  "camera": "side",
  "stance": "standing",
  "how_to": "Hold the desk, bring one heel towards your seat, lower it, then switch legs.",
  "demo_url": "https://www.youtube.com/watch?v=PpnhMmx56ag"
 },
 {
  "key": "palming",
  "label": "Palming",
  "category": "Eyes",
  "camera": "front",
  "stance": "seated",
  "how_to": "Rub your palms warm, cup them over your closed eyes for a slow breath, then lower your hands.",
  "demo_url": "https://www.youtube.com/watch?v=G1za5_1eCIw"
 },
 {
  "key": "temple_massage",
  "label": "Temple massage",
  "category": "Eyes",
  "camera": "front",
  "stance": "seated",
  "how_to": "Close your eyes, rub small slow circles on your temples with your fingertips, then lower your hands.",
  "demo_url": "https://www.youtube.com/watch?v=1-hVj9Zqcjk"
 },
 {
  "key": "look_far",
  "label": "Look into the distance",
  "category": "Eyes",
  "camera": "front",
  "stance": "seated",
  "how_to": "Turn to something far away, like a window, focus on it for a slow breath, then turn back.",
  "demo_url": "https://www.youtube.com/watch?v=6Qgp1eXmXkg"
 },
 {
  "key": "near_far_focus",
  "label": "Near-far focus",
  "category": "Eyes",
  "camera": "side",
  "stance": "seated",
  "how_to": "Thumb up at arm's length, keep it sharp as you bring it slowly to your nose, then push it back out.",
  "demo_url": "https://www.youtube.com/watch?v=rkZqDNQvblc"
 },
 {
  "key": "eye_track_vertical",
  "label": "Thumb tracking",
  "category": "Eyes",
  "camera": "side",
  "stance": "seated",
  "how_to": "Head still, follow your thumb with your eyes as you raise a straight arm up high, then lower it.",
  "demo_url": "https://www.youtube.com/watch?v=3Iu4tlovL-E"
 }
]
"""#
}
