;; SWILT WP 3 simple fab simulation - main file
;; --------------------------------------------
;;
;; requires: algorithm-XXX.nls (included from hooks.nls)
;;

__includes [ "hooks.nls"       ; hooks API for algorithms; the actual algorithms are included from there
  "helper-api.nls"             ; helper functions for algorithms implementers
  "config-reader.nls"          ; functions to read from config files
  "machines.nls"               ; functions for machines (setup, etc)
  "lots+products.nls"          ; functions for lots and products (setup, etc)
  "visualizations.nls"         ; functions for visualization + plotting
]


extensions [table]


breed [ machines machine ]
breed [ products product ]
breed [ lots lot ]
breed [ queues queue ]


machines-own [
  m.machine_type               ; machine type (=pid that can be processed)
  m.queue                      ; the queue agent associated with this machine
  m.production_time            ; time that each production process takes
  m.production_time_counter    ; counts downwards until it hits 1
  m.lots_here                  ; agentset of lots in machine during production (for both single step + batch)
  m.occupied?                  ; if machine is full
  m.utilization_ticks          ; how many ticks has machine been occupied? For caclucation of utilization
  m.batch_size                 ; how many products can go in machine
  m.max_wait_batch             ; how long to wait for a batch to fill up, waiting mechanism must be implemented by algorithm
  m.wait_timer                 ; timer, counts up to  max_wait_batch
  m.swarm_table                ; table with info for swarm algorithms - free for each algorithm to define
]


products-own [
  p.product_type               ; product type
  p.recipe                     ; recipe of product
  p.number_of_lots             ; count how often each product has to be produced
  p.RPT                        ; raw pocessing time according to recipe (for calculation of flowfactor, tardiness)
]


lots-own [
  l.lot_type                   ; lot type (=product type)
  l.prio                       ; lot priority = {"normal" | "hot"}   ; TODO: not used yet
  l.due                        ; due "date" in ticks                 ; TODO: not used yet
  l.recipe                     ; recipe of lot
  l.recipe_pointer             ; position in recipe
  l.processing?                ; lot currently processing?
  l.queued?                    ; lot currently in queue?
  l.active?                    ; is the lot still active in the simulation? Finished lots: l.active= FALSE
  l.start_time                 ; tick the lot started production
  l.end_time                   ; tick the lot ended production (goes to l.active = FALSE)
  l.RPT                        ; raw pocessing time according to recipe (for calculation of flowfactor, tardiness)
  l.movements                  ; table with history for later visualization (key=timestamp in ticks, value=action)   ; TODO: not used yet
  l.swarm_table                ; table with info for swarm algorithms - free for each algorithm to define
]


queues-own [
  q.mtype                      ; to associate with machine type (=pid)
  q.machines                   ; list of machine(s) using this queue: DISPATCHING: all m of same type share, SCHEDULING: each m has a queue
  q.color                      ; same color as associated machine type, later used for plot-pen
  q.isbatch?                   ; is this a queue for a batch machine? {TRUE|FALSE}
  q.lotlist                    ; list of lots in this queue, ie. the ACTUAL QUEUE of the lots
  q.swarm_table                ; table with info for swarm algorithms - free for each algorithm to define
]


globals [
  machines_list                ; list of all machines (agents) - used for configuration only
  product_list                 ; list of all products (agents) - used for configuration only
  lots_list                    ; list of all lots (agents) - used for configuration only
                               ;-----
  swarm_table                  ; table for algorithm implementers to store global data. table is created by setup, algorithm can immediately use
                               ;-----
                               ; queue statistics calculated by calculate-queue-length-stats - for plots and BehaviorSpace
  avg_queue_length             ; arithmetic mean of all queue lengths in the fab
  min_queue_length             ; min of all queue lengths in the fab
  max_queue_length             ; max of all queue lengths in the fab
                               ;-----
  avg_ff                       ; average lot flow factor at end of simu: total prod. time / RPT * 100 [%]
  avg_tard                     ; average lot tardiness at end of simu: total prod. time - RPT [ticks]
  avg_util                     ; average machine utilization at end of simu: ticks occupied / simu ticks total * 100 [%]
]


;-----------------------------------UI variable documentation------------------------------------------
;----- SLIDERS
; machine_types                ; the number of machine types
; total_machine_count          ; total number of machines (for example 10 - 5 type1; 3 type2; 2 type3 --- how many machines of each type is generated randomly)
; random_production_time       ; time that each production process takes (slider sets max)
; product_types                ; number of product types
; recipe_length                ; the length of recipe each product has
; max_lot_number               ; random number of lots to be produced (how many of each product type is generated randomly)
; max_wait_time_batch          ; batch machine waiting time until it starts without being full
;
;----- BUTTONS
; setup                        ; sets up the model
; step                         ; run the model step by step
; go                           ; run the model to the end of process
; clear                        ; clear the model to the initial default, ready to run again
;
;----- CHOOSERS
; DEBUG?                       ; DEBUG mode y/n?
; swarm-algorithm              ; = all installed algorithms
; allocation-strategy          ; = {"dispatching" | "scheduling"}
; Config_File?                 ; load settings from config file or use sliders for config?
;
;----- INPUTS
; config_fname                 ; the filename of the meta-configfile (string) - only used when Config_File? = TRUE
;------------------------------------------------------------------------------------------------------


;;; executed once on startup, not executed when run headless or from behavior space
;;  set sliders and choosers to default values here
;;  to avoid empty slider bug (Netlogo loading up with empty sliders causing problems)
;;
;;  HINT: if you want to save different sets of slider settings, you can use BehaviorSpace
;;        and save them as experiment settings.
;;
to startup
  set machine_types 1                ; slider default settings
  set total_machine_count machine_types
  set random_production_time 1
  set product_types 1
  set recipe_length 1
  set max_lot_number 1
  set max_wait_time_batch 1

  set DEBUG? TRUE                    ; chooser default settings
  set VIS? TRUE
  set swarm-algorithm "basic"
  set allocation-strategy "dispatching"
  set plotmode "1 Overall Queuestats (avg, max, min length)"

  set Config_File? TRUE
  set config_fname "config_simu.txt"

end



;;;-----------------------------------------------setup------------------------------------------------
to setup
  clear-all

  ifelse Config_File? [              ; read from the config file
    read-sim-config
    setup-machines-config-file
    setup-products-config-file
    setup-lots                       ; can use same procedure as slider version
    print "Setup complete, ready to Go."
  ] [                                ; use slider setup (no config file)
    setup-machines
    setup-products
    setup-lots
  ]

  set avg_queue_length 0             ; queue stats for plotting / BehaviorSpace
  set min_queue_length 0
  set max_queue_length 0

  set avg_ff   0                     ; stats for end of simu calculation
  set avg_tard 0
  set avg_util 0

  set swarm_table table:make         ; create table for global data for algorithm
  hook-init                          ; initialize algorithm

  reset-ticks
end



;;;-------------------------------------------------go-------------------------------------------------
to go
  hook-tick-start                                                                 ; callback for algorithm at tick start

  if not any? lots with [ l.active? ] [                                           ; no active lots in factory -> simulation has been ended before
    print "Simulation has ENDED\n"                                                ; probably user pressed "step" or "go" again after end
    stop
  ]

  clear-drawing                                                                   ; clear drawing after each step

  ifelse allocation-strategy = "dispatching" [                                    ; DISPATCHING
    disp-move-lot-to-queue
  ] [                                                                             ; SCHEDULING
    sched-choose-queue
  ]

  machines-take-from-queue                                                        ; DISPATCHING + SCHEDULING: algo chooses which lot(s) to take

  process-lots                                                                    ; DISPATCHING + SCHEDULING: all machines run

  if not any? lots with [ l.active? ] [                                           ; no more active lots = PRODUCTION END
    print "Simulation ENDED\n"
    do-end-calculations                                                           ; final statistics
    stop
  ]

  hook-tick-end                                                                   ; callback for algorithm at tick end

  calculate-queue-length-stats                                                    ; sets globals avg_queue_length, min_queue_length, max_queue_length

  if VIS? [                                                                       ; plot only when VIS? is on (performance)
    (ifelse first plotmode = "1" [                                                ; variadic ifelse, needs Netlogo 6.1+
      do-plotting "stats"                                                         ; plot overall stats: avg, max, min queue lengths of fab
      ]
      first plotmode = "2" [                                                      ; let the algo do the plotting
        hook-do-plotting
      ]
      first plotmode = "3" [                                                      ; plot each queue length separately (only useful in dispatching)
        do-plotting "separate"
    ])
  ]

  tick
end



;;; DISPATCHING: add lot to respective shared queue for that pid immediately, algo not involved
;;  @input    -
;;  @returns  -
;;  @context  -
;;
to disp-move-lot-to-queue
  ask lots with [ l.active? ] [
    ifelse l.recipe_pointer < length l.recipe [                                   ; lot has NOT yet finished recipe
      if l.processing? = FALSE and not l.queued? [
        let pid (item l.recipe_pointer l.recipe)
        let q one-of queues with [ q.mtype = pid ]                                ; there is only one queue per machine type
        move-to-queue q                                                           ; move + vis
      ]
    ][                                                                            ; lot has finished recipe
      vis-move-to-end max-pxcor max-pycor
      ;die                                                                        ; don't kill; keep for statistics at end of simu
      set l.end_time ticks                                                        ; current tick nr: for FF, Tardiness calculation
      set l.active? FALSE                                                         ; lot no longer in production
    ]
  ]
end



;;; SCHEDULING: algo chooses which queue the lot goes to
;;  @input    -
;;  @returns  -
;;  @context  -
;;
to sched-choose-queue
  ask lots with [ l.active? ] [
    ifelse l.recipe_pointer < length l.recipe [                                   ; lot has NOT yet finished recipe
      if l.processing? = FALSE and not l.queued? [

        let chosen_qu hook-choose-queue self                                      ; hook -> algo: chooses which queue to put lot into
        move-to-queue chosen_qu                                                   ; move + vis
      ]
    ][                                                                            ; lot has finished recipe
      vis-move-to-end max-pxcor max-pycor
      ;die                                                                        ; don't kill; keep for statistics at end of simu
      set l.end_time ticks                                                        ; current tick nr: for FF, Tardiness calculation
      set l.active? FALSE                                                         ; lot no longer in production
    ]
  ]
end



;;; SAME for DISPATCHING and SCHEDULING: algo chooses which lot to take from queue
;;  @input    -
;;  @returns  -
;;  @context  -
;;
to machines-take-from-queue
  ask machines [
    if m.occupied? = FALSE [                                                      ; machine is empty
      let taken_lots hook-take-from-queue self                                    ; hook -> algo: chooses which lot(s) to take from queue

      if VIS? [
        if any? taken_lots [                                                        ; VISUALIZATION -----
          vis-move-to-machine self taken_lots
        ]
      ]

    ]
  ]
end



;;; SAME for DISPATCHING and SCHEDULING: machines run and spend the time processing the lots
;;  @input    -
;;  @returns  -
;;  @context  -
;;
to process-lots
  ask machines with [m.occupied? = TRUE] [                                        ; all full machines process their lots
    set m.utilization_ticks m.utilization_ticks + 1                               ; for later calc of utilization

    ;------------------------------------------------------------------------------------------------single machines----------------------------------
    if m.batch_size = 1 [
      ifelse m.production_time_counter < 1 [                                      ; machine is done with processing

        move-out                                                                  ; reset production_time_counter, update machine status & lot status of m.lots_here
      ][
        set m.production_time_counter m.production_time_counter - 1               ; not finished: count production state down
      ]
    ]

    ;------------------------------------------------------------------------------------------------batch machines----------------------------------
    if m.batch_size > 1 [
      ifelse m.production_time_counter < 1 [                                      ; machine is done with processing

        move-out                                                                  ; reset production_time_counter, update machine status & lot status of m.lots_here
        set m.wait_timer 0                                                        ; resets the batch fill-up wait_timer
      ][
        set m.production_time_counter m.production_time_counter - 1               ; not finished: count production state down
      ]
    ]

  ]
end



;;; Move all lots in m.lots_here out of the machine and update lot & machine statuses, reset production_time_counter
;;  @input    -
;;  @returns  -
;;  @context  machine
;;  @note     helper function to avoid copy&paste of code in process-lots, might also be used later to fill l.movements
;;
to move-out
  hook-move-out                                                             ; call algo
  lot-state-increase m.lots_here                                            ; increases lot recipe state
  change-lot-status m.lots_here "free"                                      ; lots neither queued nor processing
  set m.production_time_counter m.production_time                           ; resets production time
  set m.occupied? FALSE                                                     ; signals that machine is free again
  set m.lots_here no-turtles                                                ; no current lots in machine
end



;;; advance lot(s) one step in the recipe (increase recipe pointer)
;;  @input    agentset of lot(s), never single lot agent
;;  @returns  -
;;  @context  -
;;
to lot-state-increase [ lotset ]
  ask lotset [
    set l.recipe_pointer l.recipe_pointer + 1                                     ; add 1 to the lot recipe state
  ]
end



;;; SCHEDULING + DISPATCHING, SINGLE + BATCH: moves a lot to the queue chosen + calls vis
;;  @input    queue agent
;;  @returns  -
;;  @context  lot
;;
to move-to-queue [ q ]

  let l self                                                                       ; called from lot context; self == current lot
  ask l [ set l.queued? TRUE ]

  ask q [
    ifelse q.isbatch? [                                                            ; BATCH machine queue -> TABLEQUEUE
      let key [l.lot_type] of l

      ifelse (table:has-key? q.lotlist key) [                                      ; existing type, get list, append l
        let templist table:get q.lotlist key
        set templist lput l templist
        table:put q.lotlist key templist
      ][                                                                           ; new type, l is first lot -> create new subqueue for this key
        let templist (list l)
        table:put q.lotlist key templist
      ]

    ][                                                                             ; SINGLE STEP machine queue -> SIMPLE LIST
      set q.lotlist lput l q.lotlist
    ]
  ]

  if VIS? [
    vis-move-to-queue q                                                              ; visualize
  ]
end



;;; Calculate queue length statistics of all machines for plotting and BehaviorSpace
;;  @input    -
;;  @returns  -
;;  @result   - sets the globals avg_queue_length
;;  @context  -
;;
to calculate-queue-length-stats

  let sum_q_len 0
  let min_q_len 9999
  let max_q_len 0
  let len 0

  ask queues [
    ifelse q.isbatch? [                                                            ; batch machine queues
      ask first q.machines [                                                       ; calculate once per queue, regardless of no of machines in dispatching mode
        set len tablequeue-get-total-length                                        ; but tablequeue function is machine context, therefore called from machine
      ]
    ][                                                                             ; single step machine queues
      set len length q.lotlist
    ]
    set sum_q_len sum_q_len + len                                                  ; calc stats
    if min_q_len > len [ set min_q_len len]
    if max_q_len < len [ set max_q_len len]
  ]

  set avg_queue_length (sum_q_len / count queues)                                  ; set global vars
  set min_queue_length min_q_len
  set max_queue_length max_q_len

end


;;; Statistics calculations for avg. flow factor, tardiness, utilization at end of simu
;;
;;  @input    - uses l.start_time, l.end_time, l_RPT and m.utilization_ticks
;;  @result   - sets the globals avg_ff, avg_tard, avg_util
;;  @context  -
to do-end-calculations

  set avg_ff 0
  set avg_tard 0
  set avg_util 0

  ask lots [                                                                       ; ff and tardiness calculation
    set avg_ff avg_ff + (l.end_time - l.start_time ) / l.RPT
    set avg_tard avg_tard + (l.end_time - l.start_time ) - l.RPT
  ]
  set avg_ff avg_ff / count lots
  set avg_tard avg_tard / count lots

  ask machines [                                                                   ; machine utilization calculation
    set avg_util avg_util + m.utilization_ticks
  ]
  set avg_util avg_util * 100 / ticks / count machines

end



;;; Statistics calculation for avg. flow factor for BehaviorSpace
;;
;;  @input    - uses l.start_time, l.end_time
;;  @result   - sets the global avg_ff
;;  @returns  - avg_ff
;;  @context  -
to-report calc-avg_ff

  set avg_ff 0
  ask lots [                                                                       ; ff calculation
    set avg_ff avg_ff + (l.end_time - l.start_time ) / l.RPT

  ]

  set avg_ff avg_ff / count lots
  report avg_ff

end



;;; Statistics calculation for avg. tardiness for BehaviorSpace
;;
;;  @input    - uses l.start_time, l.end_time, l_RPT
;;  @result   - sets the global avg_tard
;;  @returns  - avg_tard
;;  @context  -
to-report calc-avg_tard

  set avg_tard 0
  ask lots [                                                                       ; tardiness calculation
    set avg_tard avg_tard + (l.end_time - l.start_time ) - l.RPT
  ]

  set avg_tard avg_tard / count lots
  report avg_tard

end



;;; Statistics calculation for avg. utilization for BehaviorSpace
;;
;;  @input    - uses m.utilization_ticks
;;  @result   - sets the global avg_util
;;  @returns  - avg_util
;;  @context  -
to-report calc-avg_util

  set avg_util 0
  ask machines [                                                                   ; machine utilization calculation
    set avg_util avg_util + m.utilization_ticks
  ]

  set avg_util avg_util * 100 / ticks / count machines
  report avg_util

end
@#$#@#$#@
GRAPHICS-WINDOW
307
15
1221
630
-1
-1
6.0
1
9
1
1
1
0
0
0
1
0
150
0
100
0
0
1
ticks
30.0

SLIDER
6
742
293
775
machine_types
machine_types
1
floor ( (max-pycor - 2) / 4 + 1)
1.0
1
1
NIL
HORIZONTAL

BUTTON
8
129
293
170
Setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
7
822
294
855
random_production_time
random_production_time
1
10
1.0
1
1
ticks
HORIZONTAL

SLIDER
6
782
294
815
total_machine_count
total_machine_count
machine_types
max-pxcor * machine_types * 0.3
1.0
1
1
NIL
HORIZONTAL

SLIDER
6
896
293
929
product_types
product_types
1
20
1.0
1
1
NIL
HORIZONTAL

SLIDER
6
975
295
1008
max_lot_number
max_lot_number
1
10
1.0
1
1
NIL
HORIZONTAL

SLIDER
6
935
294
968
recipe_length
recipe_length
1
20
1.0
1
1
NIL
HORIZONTAL

BUTTON
10
180
112
214
Step
go
NIL
1
T
OBSERVER
NIL
S
NIL
NIL
0

BUTTON
191
180
293
215
Go
go
T
1
T
OBSERVER
NIL
G
NIL
NIL
0

SLIDER
5
859
294
892
max_wait_time_batch
max_wait_time_batch
1
5
1.0
1
1
ticks
HORIZONTAL

SWITCH
117
594
207
627
DEBUG?
DEBUG?
0
1
-1000

SWITCH
7
594
114
627
Config_File?
Config_File?
0
1
-1000

PLOT
9
272
298
524
Plot
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS

CHOOSER
154
74
292
119
allocation-strategy
allocation-strategy
"dispatching" "scheduling"
0

TEXTBOX
9
722
295
740
Manual Setup (when no config file)
11
0.0
1

CHOOSER
155
11
293
56
swarm-algorithm
swarm-algorithm
"demo" "basic" "baseline" "hormone"
0

TEXTBOX
23
24
173
42
Which swarm algorithm?
11
0.0
1

TEXTBOX
14
91
164
109
Dispatching or Scheduling?
11
0.0
1

TEXTBOX
39
231
268
269
SWILT Simulation
28
0.0
1

CHOOSER
6
532
301
577
plotmode
plotmode
"1 Overall Queuestats (avg, max, min length)" "2 Algorithm (if algo supports it)" "3 Separate Queues (only use in dispatching)"
0

INPUTBOX
6
636
300
696
config_fname
config_DEMO_simu.txt
1
0
String

SWITCH
210
594
300
627
VIS?
VIS?
0
1
-1000

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

batch_machine
false
0
Rectangle -7500403 true true 30 30 270 270
Line -16777216 false 150 30 150 270
Line -16777216 false 30 150 270 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.2.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="Experiment-ICAART-Baseline" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;baseline&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_ICAART_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-LARGE-1-Baseline" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;baseline&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_LARGE-1_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-MEDIUM-1-Baseline" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;baseline&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_MEDIUM-1_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-SFAB-Baseline" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;baseline&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_SFAB_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-ICAART-Basic" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;basic&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_ICAART_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-LARGE-1-Basic" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;basic&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_LARGE-1_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-MEDIUM-1-Basic" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;basic&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_MEDIUM-1_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-SFAB-Basic" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;basic&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_SFAB_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-ICAART-ABC" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;abc&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_ICAART_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-LARGE-1-ABC" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;abc&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_LARGE-1_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-MEDIUM-1-ABC" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;abc&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_MEDIUM-1_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-SFAB-ABC" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;abc&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_SFAB_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-ICAART-Ant" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;ant&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_ICAART_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-LARGE-1-Ant" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;ant&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_LARGE-1_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-MEDIUM-1-Ant" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;ant&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_MEDIUM-1_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-SFAB-Ant" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;ant&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_SFAB_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-ICAART-Slime" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;slime&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_ICAART_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-LARGE-1-Slime" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;slime&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_LARGE-1_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-MEDIUM-1-Slime" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;slime&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_MEDIUM-1_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-SFAB-Slime" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;slime&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;scheduling&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_SFAB_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-ICAART-Hormone" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;hormone&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;dispatching&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_ICAART_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-LARGE-1-Hormone" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;hormone&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;dispatching&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_LARGE-1_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-MEDIUM-1-Hormone" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;hormone&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;dispatching&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_MEDIUM-1_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Experiment-SFAB-Hormone" repetitions="30" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>do-end-calculations
file-open (word "results/SWILT-Simulation " behaviorspace-experiment-name "-kpis.csv")
file-print (word behaviorspace-run-number  " " avg_ff " " avg_tard " " avg_util)
file-close</final>
    <exitCondition>(count lots with [l.active?] = 0)</exitCondition>
    <metric>avg_queue_length</metric>
    <metric>max_queue_length</metric>
    <metric>min_queue_length</metric>
    <enumeratedValueSet variable="swarm-algorithm">
      <value value="&quot;hormone&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="allocation-strategy">
      <value value="&quot;dispatching&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Config_File?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="config_fname">
      <value value="&quot;config_SFAB_simu.txt&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="DEBUG?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="VIS?">
      <value value="false"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
