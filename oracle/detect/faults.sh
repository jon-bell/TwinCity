# Fault injectors for the UB detector builds (build-detect.sh, build-detect-xvfb.sh). Sourced.
# Each takes the tree's src/sim directory and edits it in place; each fails loudly if it did
# not apply. None changes a line count, so file:line stays the upstream line.
#   fault_plant  before the rewrite: three UB sites on blank lines of s_sim.c. On :93, a global
#                overflow and a signed overflow; on :105, a Map row overrun, which also checks
#                that it lands on Map[4][0] (read without TC_AT).
#   fault_steer_shift      after the rewrite: the detect-side TC_AT shifts every column
#                          subscript by one (headless: red on all 32 sessions).
#   fault_steer_transpose  after the rewrite: the detect-side TC_AT transposes every access inside
#                          the square [0,min(X,Y))^2. The GUI build needs this one: a uniform shift
#                          also moves the raw-pointer bases taken as TC_AT(...,0,0) (file load,
#                          animateTiles, the renderers), so the app relabels the map consistently
#                          and nothing visible changes. The transpose is the identity at [0][0].
#   fault_swap   after the rewrite: the compiled-out TC_AT swaps its subscripts.
# Neither steer nor swap is the original access.
fault_plant() {
  for n in 93 105; do sed -n ${n}p "$1/s_sim.c" | grep -q '^$' || { echo "plant: s_sim.c:$n is not blank" >&2; exit 2; }; done
  sed -i '93s/.*/  { volatile int tc_k = 0; volatile short tc_p; volatile int tc_big = 2147483647; tc_p = FireStMap[SmX + tc_k][0]; tc_big = tc_big + (tc_k == 0); }/' "$1/s_sim.c"
  sed -i '105s/.*/  { volatile short tc_p = Map[3][WORLD_Y]; if (\&Map[3][WORLD_Y] != *(Map + 4)) printf("plant: row overrun did not land on Map[4][0]\\n"); }/' "$1/s_sim.c"
}
fault_steer_shift() {
  sed -i 's/&A\[tc_a_\]\[tc_b_\]; }))/\&A[tc_a_][(tc_b_ + 1) % (Y)]; }))/' "$1/headers/sim.h"
  grep -q '(tc_b_ + 1) % (Y)' "$1/headers/sim.h" || { echo "steer fault did not apply" >&2; exit 2; }
}
fault_steer_transpose() {
  sed -i 's/&A\[tc_a_\]\[tc_b_\]; }))/(tc_a_ < (Y) \&\& tc_b_ < (X) ? \&A[tc_b_][tc_a_] : \&A[tc_a_][tc_b_]); }))/' "$1/headers/sim.h"
  grep -q '? &A\[tc_b_\]\[tc_a_\] :' "$1/headers/sim.h" || { echo "steer fault did not apply" >&2; exit 2; }
}
fault_swap() {
  sed -i 's/^#define TC_AT(A, X, Y, a, b) A\[a\]\[b\]$/#define TC_AT(A, X, Y, a, b) A[b][a]/' "$1/headers/sim.h"
  grep -q 'A\[b\]\[a\]' "$1/headers/sim.h" || { echo "swap fault did not apply" >&2; exit 2; }
}
