/// Standard ImageNet-1K class labels (1000 entries).
///
/// These are the canonical class names used by models trained on ImageNet-1K,
/// indexed by class ID (0–999). Used by `ImageClassifier` to map logit indices
/// to human-readable labels.
///
/// Source: https://image-net.org/challenges/LSVRC/
public enum ImageNetLabels {
    /// All 1000 ImageNet-1K class labels, in class-ID order.
    public static let labels: [String] = [
        "tench",                          // 0
        "goldfish",                       // 1
        "great white shark",              // 2
        "tiger shark",                    // 3
        "hammerhead shark",               // 4
        "electric ray",                   // 5
        "stingray",                       // 6
        "rooster",                        // 7
        "hen",                            // 8
        "ostrich",                        // 9
        "brambling",                      // 10
        "goldfinch",                      // 11
        "house finch",                    // 12
        "junco",                          // 13
        "indigo bunting",                 // 14
        "American robin",                 // 15
        "bulbul",                         // 16
        "jay",                            // 17
        "magpie",                         // 18
        "chickadee",                      // 19
        "American dipper",               // 20
        "kite",                           // 21
        "bald eagle",                     // 22
        "vulture",                        // 23
        "great grey owl",                 // 24
        "fire salamander",                // 25
        "smooth newt",                    // 26
        "newt",                           // 27
        "spotted salamander",             // 28
        "axolotl",                        // 29
        "American bullfrog",              // 30
        "tree frog",                      // 31
        "tailed frog",                    // 32
        "loggerhead sea turtle",          // 33
        "leatherback sea turtle",         // 34
        "mud turtle",                     // 35
        "terrapin",                       // 36
        "box turtle",                     // 37
        "banded gecko",                   // 38
        "green iguana",                   // 39
        "Carolina anole",                 // 40
        "desert grassland whiptail lizard", // 41
        "agama",                          // 42
        "frilled-neck lizard",            // 43
        "alligator lizard",               // 44
        "Gila monster",                   // 45
        "European green lizard",          // 46
        "chameleon",                      // 47
        "Komodo dragon",                  // 48
        "Nile crocodile",                 // 49
        "American alligator",             // 50
        "triceratops",                    // 51
        "worm snake",                     // 52
        "ring-necked snake",              // 53
        "eastern hog-nosed snake",        // 54
        "smooth green snake",             // 55
        "kingsnake",                      // 56
        "garter snake",                   // 57
        "water snake",                    // 58
        "vine snake",                     // 59
        "night snake",                    // 60
        "boa constrictor",                // 61
        "African rock python",            // 62
        "Indian cobra",                   // 63
        "green mamba",                    // 64
        "sea snake",                      // 65
        "Saharan horned viper",           // 66
        "eastern diamondback rattlesnake", // 67
        "sidewinder rattlesnake",         // 68
        "trilobite",                      // 69
        "harvestman",                     // 70
        "scorpion",                       // 71
        "yellow garden spider",           // 72
        "barn spider",                    // 73
        "European garden spider",         // 74
        "southern black widow",           // 75
        "tarantula",                      // 76
        "wolf spider",                    // 77
        "tick",                           // 78
        "centipede",                      // 79
        "black grouse",                   // 80
        "ptarmigan",                      // 81
        "ruffed grouse",                  // 82
        "prairie grouse",                 // 83
        "peacock",                        // 84
        "quail",                          // 85
        "partridge",                      // 86
        "African grey parrot",            // 87
        "macaw",                          // 88
        "sulphur-crested cockatoo",       // 89
        "lorikeet",                       // 90
        "coucal",                         // 91
        "bee eater",                      // 92
        "hornbill",                       // 93
        "hummingbird",                    // 94
        "jacamar",                        // 95
        "toucan",                         // 96
        "duck",                           // 97
        "red-breasted merganser",         // 98
        "goose",                          // 99
        "black swan",                     // 100
        "tusker",                         // 101
        "echidna",                        // 102
        "platypus",                       // 103
        "wallaby",                        // 104
        "koala",                          // 105
        "wombat",                         // 106
        "jellyfish",                      // 107
        "sea anemone",                    // 108
        "brain coral",                    // 109
        "flatworm",                       // 110
        "nematode",                       // 111
        "conch",                          // 112
        "snail",                          // 113
        "slug",                           // 114
        "sea slug",                       // 115
        "chiton",                         // 116
        "chambered nautilus",             // 117
        "Dungeness crab",                 // 118
        "rock crab",                      // 119
        "fiddler crab",                   // 120
        "red king crab",                  // 121
        "American lobster",               // 122
        "spiny lobster",                  // 123
        "crayfish",                       // 124
        "hermit crab",                    // 125
        "isopod",                         // 126
        "white stork",                    // 127
        "black stork",                    // 128
        "spoonbill",                      // 129
        "flamingo",                       // 130
        "little blue heron",              // 131
        "great egret",                    // 132
        "bittern",                        // 133
        "crane bird",                     // 134
        "limpkin",                        // 135
        "common gallinule",               // 136
        "American coot",                  // 137
        "bustard",                        // 138
        "ruddy turnstone",                // 139
        "dunlin",                         // 140
        "common redshank",                // 141
        "dowitcher",                      // 142
        "oystercatcher",                  // 143
        "pelican",                        // 144
        "king penguin",                   // 145
        "albatross",                      // 146
        "grey whale",                     // 147
        "killer whale",                   // 148
        "dugong",                         // 149
        "sea lion",                       // 150
        "Chihuahua",                      // 151
        "Japanese Chin",                  // 152
        "Maltese",                        // 153
        "Pekingese",                      // 154
        "Shih Tzu",                       // 155
        "King Charles Spaniel",           // 156
        "Papillon",                       // 157
        "toy terrier",                    // 158
        "Rhodesian Ridgeback",            // 159
        "Afghan Hound",                   // 160
        "Basset Hound",                   // 161
        "Beagle",                         // 162
        "Bloodhound",                     // 163
        "Bluetick Coonhound",             // 164
        "Black and Tan Coonhound",        // 165
        "Treeing Walker Coonhound",       // 166
        "English Foxhound",               // 167
        "Redbone Coonhound",              // 168
        "borzoi",                         // 169
        "Irish Wolfhound",                // 170
        "Italian Greyhound",              // 171
        "Whippet",                        // 172
        "Ibizan Hound",                   // 173
        "Norwegian Elkhound",             // 174
        "Otterhound",                     // 175
        "Saluki",                         // 176
        "Scottish Deerhound",             // 177
        "Weimaraner",                     // 178
        "Staffordshire Bull Terrier",     // 179
        "American Staffordshire Terrier", // 180
        "Bedlington Terrier",             // 181
        "Border Terrier",                 // 182
        "Kerry Blue Terrier",             // 183
        "Irish Terrier",                  // 184
        "Norfolk Terrier",                // 185
        "Norwich Terrier",                // 186
        "Yorkshire Terrier",              // 187
        "Wire Fox Terrier",               // 188
        "Lakeland Terrier",               // 189
        "Sealyham Terrier",               // 190
        "Airedale Terrier",               // 191
        "Cairn Terrier",                  // 192
        "Australian Terrier",             // 193
        "Dandie Dinmont Terrier",         // 194
        "Boston Terrier",                 // 195
        "Miniature Schnauzer",            // 196
        "Giant Schnauzer",                // 197
        "Standard Schnauzer",             // 198
        "Scottish Terrier",               // 199
        "Tibetan Terrier",                // 200
        "Australian Silky Terrier",       // 201
        "Soft-coated Wheaten Terrier",    // 202
        "West Highland White Terrier",    // 203
        "Lhasa Apso",                     // 204
        "Flat-Coated Retriever",          // 205
        "Curly-coated Retriever",         // 206
        "Golden Retriever",               // 207
        "Labrador Retriever",             // 208
        "Chesapeake Bay Retriever",       // 209
        "German Shorthaired Pointer",     // 210
        "Vizsla",                         // 211
        "English Setter",                 // 212
        "Irish Setter",                   // 213
        "Gordon Setter",                  // 214
        "Brittany",                       // 215
        "Clumber Spaniel",                // 216
        "English Springer Spaniel",       // 217
        "Welsh Springer Spaniel",         // 218
        "Cocker Spaniels",                // 219
        "Sussex Spaniel",                 // 220
        "Irish Water Spaniel",            // 221
        "Kuvasz",                         // 222
        "Schipperke",                     // 223
        "Groenendael",                    // 224
        "Malinois",                       // 225
        "Briard",                         // 226
        "Australian Kelpie",              // 227
        "Komondor",                       // 228
        "Old English Sheepdog",           // 229
        "Shetland Sheepdog",              // 230
        "collie",                         // 231
        "Border Collie",                  // 232
        "Bouvier des Flandres",           // 233
        "Rottweiler",                     // 234
        "German Shepherd Dog",            // 235
        "Dobermann",                      // 236
        "Miniature Pinscher",             // 237
        "Greater Swiss Mountain Dog",     // 238
        "Bernese Mountain Dog",           // 239
        "Appenzeller Sennenhund",         // 240
        "Entlebucher Sennenhund",         // 241
        "Boxer",                          // 242
        "Bullmastiff",                    // 243
        "Tibetan Mastiff",                // 244
        "French Bulldog",                 // 245
        "Great Dane",                     // 246
        "St. Bernard",                    // 247
        "husky",                          // 248
        "Alaskan Malamute",               // 249
        "Siberian Husky",                 // 250
        "Dalmatian",                      // 251
        "Affenpinscher",                  // 252
        "Basenji",                        // 253
        "pug",                            // 254
        "Leonberger",                     // 255
        "Newfoundland",                   // 256
        "Pyrenean Mountain Dog",          // 257
        "Samoyed",                        // 258
        "Pomeranian",                     // 259
        "Chow Chow",                      // 260
        "Keeshond",                       // 261
        "Griffon Bruxellois",             // 262
        "Pembroke Welsh Corgi",           // 263
        "Cardigan Welsh Corgi",           // 264
        "Toy Poodle",                     // 265
        "Miniature Poodle",               // 266
        "Standard Poodle",                // 267
        "Mexican hairless dog",           // 268
        "grey wolf",                      // 269
        "Alaskan tundra wolf",            // 270
        "red wolf",                       // 271
        "coyote",                         // 272
        "dingo",                          // 273
        "dhole",                          // 274
        "African wild dog",               // 275
        "hyena",                          // 276
        "red fox",                        // 277
        "kit fox",                        // 278
        "Arctic fox",                     // 279
        "grey fox",                       // 280
        "tabby cat",                      // 281
        "tiger cat",                      // 282
        "Persian cat",                    // 283
        "Siamese cat",                    // 284
        "Egyptian Mau",                   // 285
        "cougar",                         // 286
        "lynx",                           // 287
        "leopard",                        // 288
        "snow leopard",                   // 289
        "jaguar",                         // 290
        "lion",                           // 291
        "tiger",                          // 292
        "cheetah",                        // 293
        "brown bear",                     // 294
        "American black bear",            // 295
        "polar bear",                     // 296
        "sloth bear",                     // 297
        "mongoose",                       // 298
        "meerkat",                        // 299
        "tiger beetle",                   // 300
        "ladybug",                        // 301
        "ground beetle",                  // 302
        "longhorn beetle",                // 303
        "leaf beetle",                    // 304
        "dung beetle",                    // 305
        "rhinoceros beetle",              // 306
        "weevil",                         // 307
        "fly",                            // 308
        "bee",                            // 309
        "ant",                            // 310
        "grasshopper",                    // 311
        "cricket insect",                 // 312
        "stick insect",                   // 313
        "cockroach",                      // 314
        "praying mantis",                 // 315
        "cicada",                         // 316
        "leafhopper",                     // 317
        "lacewing",                       // 318
        "dragonfly",                      // 319
        "damselfly",                      // 320
        "red admiral butterfly",          // 321
        "ringlet butterfly",              // 322
        "monarch butterfly",              // 323
        "small white butterfly",          // 324
        "sulphur butterfly",              // 325
        "gossamer-winged butterfly",      // 326
        "starfish",                       // 327
        "sea urchin",                     // 328
        "sea cucumber",                   // 329
        "cottontail rabbit",              // 330
        "hare",                           // 331
        "Angora rabbit",                  // 332
        "hamster",                        // 333
        "porcupine",                      // 334
        "fox squirrel",                   // 335
        "marmot",                         // 336
        "beaver",                         // 337
        "guinea pig",                     // 338
        "common sorrel horse",            // 339
        "zebra",                          // 340
        "pig",                            // 341
        "wild boar",                      // 342
        "warthog",                        // 343
        "hippopotamus",                   // 344
        "ox",                             // 345
        "water buffalo",                  // 346
        "bison",                          // 347
        "ram",                            // 348
        "bighorn sheep",                  // 349
        "Alpine ibex",                    // 350
        "hartebeest",                     // 351
        "impala",                         // 352
        "gazelle",                        // 353
        "arabian camel",                  // 354
        "llama",                          // 355
        "weasel",                         // 356
        "mink",                           // 357
        "European polecat",               // 358
        "black-footed ferret",            // 359
        "otter",                          // 360
        "skunk",                          // 361
        "badger",                         // 362
        "armadillo",                      // 363
        "three-toed sloth",               // 364
        "orangutan",                      // 365
        "gorilla",                        // 366
        "chimpanzee",                     // 367
        "gibbon",                         // 368
        "siamang",                        // 369
        "guenon",                         // 370
        "patas monkey",                   // 371
        "baboon",                         // 372
        "macaque",                        // 373
        "langur",                         // 374
        "black-and-white colobus",        // 375
        "proboscis monkey",               // 376
        "marmoset",                       // 377
        "white-headed capuchin",          // 378
        "howler monkey",                  // 379
        "titi monkey",                    // 380
        "Geoffroy's spider monkey",       // 381
        "common squirrel monkey",         // 382
        "ring-tailed lemur",              // 383
        "indri",                          // 384
        "Asian elephant",                 // 385
        "African bush elephant",          // 386
        "red panda",                      // 387
        "giant panda",                    // 388
        "snoek fish",                     // 389
        "eel",                            // 390
        "silver salmon",                  // 391
        "rock beauty fish",               // 392
        "clownfish",                      // 393
        "sturgeon",                       // 394
        "gar fish",                       // 395
        "lionfish",                       // 396
        "pufferfish",                     // 397
        "abacus",                         // 398
        "abaya",                          // 399
        "academic gown",                  // 400
        "accordion",                      // 401
        "acoustic guitar",                // 402
        "aircraft carrier",               // 403
        "airliner",                       // 404
        "airship",                        // 405
        "altar",                          // 406
        "ambulance",                      // 407
        "amphibious vehicle",             // 408
        "analog clock",                   // 409
        "apiary",                         // 410
        "apron",                          // 411
        "trash can",                      // 412
        "assault rifle",                  // 413
        "backpack",                       // 414
        "bakery",                         // 415
        "balance beam",                   // 416
        "balloon",                        // 417
        "ballpoint pen",                  // 418
        "Band-Aid",                       // 419
        "banjo",                          // 420
        "baluster",                       // 421
        "barbell",                        // 422
        "barber chair",                   // 423
        "barbershop",                     // 424
        "barn",                           // 425
        "barometer",                      // 426
        "barrel",                         // 427
        "wheelbarrow",                    // 428
        "baseball",                       // 429
        "basketball",                     // 430
        "bassinet",                       // 431
        "bassoon",                        // 432
        "swimming cap",                   // 433
        "bath towel",                     // 434
        "bathtub",                        // 435
        "station wagon",                  // 436
        "lighthouse",                     // 437
        "beaker",                         // 438
        "military hat",                   // 439
        "beer bottle",                    // 440
        "beer glass",                     // 441
        "bell tower",                     // 442
        "baby bib",                       // 443
        "tandem bicycle",                 // 444
        "bikini",                         // 445
        "ring binder",                    // 446
        "binoculars",                     // 447
        "birdhouse",                      // 448
        "boathouse",                      // 449
        "bobsleigh",                      // 450
        "bolo tie",                       // 451
        "poke bonnet",                    // 452
        "bookcase",                       // 453
        "bookstore",                      // 454
        "bottle cap",                     // 455
        "hunting bow",                    // 456
        "bow tie",                        // 457
        "brass memorial plaque",          // 458
        "bra",                            // 459
        "breakwater",                     // 460
        "breastplate",                    // 461
        "broom",                          // 462
        "bucket",                         // 463
        "buckle",                         // 464
        "bulletproof vest",               // 465
        "high-speed train",               // 466
        "butcher shop",                   // 467
        "taxicab",                        // 468
        "cauldron",                       // 469
        "candle",                         // 470
        "cannon",                         // 471
        "canoe",                          // 472
        "can opener",                     // 473
        "cardigan",                       // 474
        "car mirror",                     // 475
        "carousel",                       // 476
        "tool kit",                       // 477
        "cardboard box",                  // 478
        "car wheel",                      // 479
        "automated teller machine",       // 480
        "cassette",                       // 481
        "cassette player",                // 482
        "castle",                         // 483
        "catamaran",                      // 484
        "CD player",                      // 485
        "cello",                          // 486
        "mobile phone",                   // 487
        "chain",                          // 488
        "chain-link fence",               // 489
        "chain mail",                     // 490
        "chainsaw",                       // 491
        "storage chest",                  // 492
        "chiffonier",                     // 493
        "bell",                           // 494
        "china cabinet",                  // 495
        "Christmas stocking",             // 496
        "church",                         // 497
        "movie theater",                  // 498
        "cleaver",                        // 499
        "cliff dwelling",                 // 500
        "cloak",                          // 501
        "clogs",                          // 502
        "cocktail shaker",                // 503
        "coffee mug",                     // 504
        "coffeemaker",                    // 505
        "spiral or coil",                 // 506
        "combination lock",               // 507
        "computer keyboard",              // 508
        "candy store",                    // 509
        "container ship",                 // 510
        "convertible",                    // 511
        "corkscrew",                      // 512
        "cornet",                         // 513
        "cowboy boot",                    // 514
        "cowboy hat",                     // 515
        "cradle",                         // 516
        "construction crane",             // 517
        "crash helmet",                   // 518
        "crate",                          // 519
        "infant bed",                     // 520
        "Crock Pot",                      // 521
        "croquet ball",                   // 522
        "crutch",                         // 523
        "cuirass",                        // 524
        "dam",                            // 525
        "desk",                           // 526
        "desktop computer",               // 527
        "rotary dial telephone",          // 528
        "diaper",                         // 529
        "digital clock",                  // 530
        "digital watch",                  // 531
        "dining table",                   // 532
        "dishcloth",                      // 533
        "dishwasher",                     // 534
        "disc brake",                     // 535
        "dock",                           // 536
        "dog sled",                       // 537
        "dome",                           // 538
        "doormat",                        // 539
        "drilling rig",                   // 540
        "drum",                           // 541
        "drumstick",                      // 542
        "dumbbell",                       // 543
        "Dutch oven",                     // 544
        "electric fan",                   // 545
        "electric guitar",                // 546
        "electric locomotive",            // 547
        "entertainment center",           // 548
        "envelope",                       // 549
        "espresso machine",               // 550
        "face powder",                    // 551
        "feather boa",                    // 552
        "filing cabinet",                 // 553
        "fireboat",                       // 554
        "fire truck",                     // 555
        "fire screen",                    // 556
        "flagpole",                       // 557
        "flute",                          // 558
        "folding chair",                  // 559
        "football helmet",                // 560
        "forklift",                       // 561
        "fountain",                       // 562
        "fountain pen",                   // 563
        "four-poster bed",                // 564
        "freight car",                    // 565
        "French horn",                    // 566
        "frying pan",                     // 567
        "fur coat",                       // 568
        "garbage truck",                  // 569
        "gas mask",                       // 570
        "gas pump",                       // 571
        "goblet",                         // 572
        "go-kart",                        // 573
        "golf ball",                      // 574
        "golf cart",                      // 575
        "gondola",                        // 576
        "gong",                           // 577
        "gown",                           // 578
        "grand piano",                    // 579
        "greenhouse",                     // 580
        "radiator grille",                // 581
        "grocery store",                  // 582
        "guillotine",                     // 583
        "hair clip",                      // 584
        "hair spray",                     // 585
        "half-track",                     // 586
        "hammer",                         // 587
        "hamper",                         // 588
        "hair dryer",                     // 589
        "hand-held computer",             // 590
        "handkerchief",                   // 591
        "hard disk drive",                // 592
        "harmonica",                      // 593
        "harp",                           // 594
        "combine harvester",              // 595
        "hatchet",                        // 596
        "holster",                        // 597
        "home theater",                   // 598
        "honeycomb",                      // 599
        "hook",                           // 600
        "hoop skirt",                     // 601
        "gymnastic horizontal bar",       // 602
        "horse-drawn vehicle",            // 603
        "hourglass",                      // 604
        "iPod",                           // 605
        "clothes iron",                   // 606
        "carved pumpkin",                 // 607
        "jeans",                          // 608
        "jeep",                           // 609
        "T-shirt",                        // 610
        "jigsaw puzzle",                  // 611
        "rickshaw",                       // 612
        "joystick",                       // 613
        "kimono",                         // 614
        "knee pad",                       // 615
        "knot",                           // 616
        "lab coat",                       // 617
        "ladle",                          // 618
        "lampshade",                      // 619
        "laptop computer",                // 620
        "lawn mower",                     // 621
        "lens cap",                       // 622
        "letter opener",                  // 623
        "library",                        // 624
        "lifeboat",                       // 625
        "lighter",                        // 626
        "limousine",                      // 627
        "ocean liner",                    // 628
        "lipstick",                       // 629
        "slip-on shoe",                   // 630
        "lotion",                         // 631
        "music speaker",                  // 632
        "loupe magnifying glass",         // 633
        "sawmill",                        // 634
        "magnetic compass",               // 635
        "messenger bag",                  // 636
        "mailbox",                        // 637
        "tights",                         // 638
        "one-piece bathing suit",         // 639
        "manhole cover",                  // 640
        "maraca",                         // 641
        "marimba",                        // 642
        "mask",                           // 643
        "matchstick",                     // 644
        "maypole",                        // 645
        "maze",                           // 646
        "measuring cup",                  // 647
        "medicine cabinet",               // 648
        "megalith",                       // 649
        "microphone",                     // 650
        "microwave oven",                 // 651
        "military uniform",               // 652
        "milk can",                       // 653
        "minibus",                        // 654
        "miniskirt",                      // 655
        "minivan",                        // 656
        "missile",                        // 657
        "mitten",                         // 658
        "mixing bowl",                    // 659
        "mobile home",                    // 660
        "Ford Model T",                   // 661
        "modem",                          // 662
        "monastery",                      // 663
        "monitor",                        // 664
        "moped",                          // 665
        "mortar and pestle",              // 666
        "graduation cap",                 // 667
        "mosque",                         // 668
        "mosquito net",                   // 669
        "vespa",                          // 670
        "mountain bike",                  // 671
        "tent",                           // 672
        "computer mouse",                 // 673
        "mousetrap",                      // 674
        "moving van",                     // 675
        "muzzle",                         // 676
        "metal nail",                     // 677
        "neck brace",                     // 678
        "necklace",                       // 679
        "baby pacifier",                  // 680
        "notebook computer",              // 681
        "obelisk",                        // 682
        "oboe",                           // 683
        "ocarina",                        // 684
        "odometer",                       // 685
        "oil filter",                     // 686
        "pipe organ",                     // 687
        "oscilloscope",                   // 688
        "overskirt",                      // 689
        "bullock cart",                   // 690
        "oxygen mask",                    // 691
        "product packet",                 // 692
        "paddle",                         // 693
        "paddle wheel",                   // 694
        "padlock",                        // 695
        "paintbrush",                     // 696
        "pajamas",                        // 697
        "palace",                         // 698
        "pan flute",                      // 699
        "paper towel",                    // 700
        "parachute",                      // 701
        "parallel bars",                  // 702
        "park bench",                     // 703
        "parking meter",                  // 704
        "railroad car",                   // 705
        "patio",                          // 706
        "pay phone",                      // 707
        "pedestal",                       // 708
        "pencil case",                    // 709
        "pencil sharpener",               // 710
        "perfume",                        // 711
        "Petri dish",                     // 712
        "photocopier",                    // 713
        "plectrum",                       // 714
        "Pickelhaube",                    // 715
        "picket fence",                   // 716
        "pickup truck",                   // 717
        "pier",                           // 718
        "piggy bank",                     // 719
        "pill bottle",                    // 720
        "pillow",                         // 721
        "ping-pong ball",                 // 722
        "pinwheel",                       // 723
        "pirate ship",                    // 724
        "drink pitcher",                  // 725
        "block plane",                    // 726
        "planetarium",                    // 727
        "plastic bag",                    // 728
        "plate rack",                     // 729
        "farm plow",                      // 730
        "plunger",                        // 731
        "Polaroid camera",                // 732
        "pole",                           // 733
        "police van",                     // 734
        "poncho",                         // 735
        "billiard table",                 // 736
        "soda bottle",                    // 737
        "plant pot",                      // 738
        "potter's wheel",                 // 739
        "power drill",                    // 740
        "prayer rug",                     // 741
        "printer",                        // 742
        "prison",                         // 743
        "projectile",                     // 744
        "projector",                      // 745
        "hockey puck",                    // 746
        "punching bag",                   // 747
        "purse",                          // 748
        "quill",                          // 749
        "quilt",                          // 750
        "race car",                       // 751
        "racket",                         // 752
        "radiator",                       // 753
        "radio",                          // 754
        "radio telescope",                // 755
        "rain barrel",                    // 756
        "recreational vehicle",           // 757
        "fishing casting reel",           // 758
        "reflex camera",                  // 759
        "refrigerator",                   // 760
        "remote control",                 // 761
        "restaurant",                     // 762
        "revolver",                       // 763
        "rifle",                          // 764
        "rocking chair",                  // 765
        "rotisserie",                     // 766
        "eraser",                         // 767
        "rugby ball",                     // 768
        "ruler measuring stick",          // 769
        "running shoe",                   // 770
        "safe",                           // 771
        "safety pin",                     // 772
        "salt shaker",                    // 773
        "sandal",                         // 774
        "sarong",                         // 775
        "saxophone",                      // 776
        "scabbard",                       // 777
        "weighing scale",                 // 778
        "school bus",                     // 779
        "schooner",                       // 780
        "scoreboard",                     // 781
        "CRT screen",                     // 782
        "screw",                          // 783
        "screwdriver",                    // 784
        "seat belt",                      // 785
        "sewing machine",                 // 786
        "shield",                         // 787
        "shoe store",                     // 788
        "shoji screen",                   // 789
        "shopping basket",                // 790
        "shopping cart",                  // 791
        "shovel",                         // 792
        "shower cap",                     // 793
        "shower curtain",                 // 794
        "ski",                            // 795
        "balaclava ski mask",             // 796
        "sleeping bag",                   // 797
        "slide rule",                     // 798
        "sliding door",                   // 799
        "slot machine",                   // 800
        "snorkel",                        // 801
        "snowmobile",                     // 802
        "snowplow",                       // 803
        "soap dispenser",                 // 804
        "soccer ball",                    // 805
        "sock",                           // 806
        "solar thermal collector",        // 807
        "sombrero",                       // 808
        "soup bowl",                      // 809
        "keyboard space bar",             // 810
        "space heater",                   // 811
        "space shuttle",                  // 812
        "spatula",                        // 813
        "motorboat",                      // 814
        "spider web",                     // 815
        "spindle",                        // 816
        "sports car",                     // 817
        "spotlight",                      // 818
        "stage",                          // 819
        "steam locomotive",               // 820
        "through arch bridge",            // 821
        "steel drum",                     // 822
        "stethoscope",                    // 823
        "scarf",                          // 824
        "stone wall",                     // 825
        "stopwatch",                      // 826
        "stove",                          // 827
        "strainer",                       // 828
        "tram",                           // 829
        "stretcher",                      // 830
        "couch",                          // 831
        "stupa",                          // 832
        "submarine",                      // 833
        "suit",                           // 834
        "sundial",                        // 835
        "sunglasses",                     // 836
        "sunscreen",                      // 837
        "suspension bridge",              // 838
        "mop",                            // 839
        "sweatshirt",                     // 840
        "swim trunks",                    // 841
        "swing",                          // 842
        "electrical switch",              // 843
        "syringe",                        // 844
        "table lamp",                     // 845
        "tank",                           // 846
        "tape player",                    // 847
        "teapot",                         // 848
        "teddy bear",                     // 849
        "television",                     // 850
        "tennis ball",                    // 851
        "thatched roof",                  // 852
        "front curtain",                  // 853
        "thimble",                        // 854
        "threshing machine",              // 855
        "throne",                         // 856
        "tile roof",                      // 857
        "toaster",                        // 858
        "tobacco shop",                   // 859
        "toilet seat",                    // 860
        "torch",                          // 861
        "totem pole",                     // 862
        "tow truck",                      // 863
        "toy store",                      // 864
        "tractor",                        // 865
        "semi-trailer truck",             // 866
        "tray",                           // 867
        "trench coat",                    // 868
        "tricycle",                       // 869
        "trimaran",                       // 870
        "tripod",                         // 871
        "triumphal arch",                 // 872
        "trolleybus",                     // 873
        "trombone",                       // 874
        "hot tub",                        // 875
        "turnstile",                      // 876
        "typewriter keyboard",            // 877
        "umbrella",                       // 878
        "unicycle",                       // 879
        "upright piano",                  // 880
        "vacuum cleaner",                 // 881
        "vase",                           // 882
        "vaulted or arched ceiling",      // 883
        "velvet fabric",                  // 884
        "vending machine",                // 885
        "vestment",                       // 886
        "viaduct",                        // 887
        "violin",                         // 888
        "volleyball",                     // 889
        "waffle iron",                    // 890
        "wall clock",                     // 891
        "wallet",                         // 892
        "wardrobe",                       // 893
        "military aircraft",              // 894
        "sink",                           // 895
        "washing machine",                // 896
        "water bottle",                   // 897
        "water jug",                      // 898
        "water tower",                    // 899
        "whiskey jug",                    // 900
        "whistle",                        // 901
        "hair wig",                       // 902
        "window screen",                  // 903
        "window shade",                   // 904
        "Windsor tie",                    // 905
        "wine bottle",                    // 906
        "wing",                           // 907
        "wok",                            // 908
        "wooden spoon",                   // 909
        "wool",                           // 910
        "split-rail fence",               // 911
        "shipwreck",                      // 912
        "sailboat",                       // 913
        "yurt",                           // 914
        "website",                        // 915
        "comic book",                     // 916
        "crossword",                      // 917
        "traffic or street sign",         // 918
        "traffic light",                  // 919
        "dust jacket",                    // 920
        "menu",                           // 921
        "plate",                          // 922
        "guacamole",                      // 923
        "consomme",                       // 924
        "hot pot",                        // 925
        "trifle",                         // 926
        "ice cream",                      // 927
        "popsicle",                       // 928
        "baguette",                       // 929
        "bagel",                          // 930
        "pretzel",                        // 931
        "cheeseburger",                   // 932
        "hot dog",                        // 933
        "mashed potatoes",                // 934
        "cabbage",                        // 935
        "broccoli",                       // 936
        "cauliflower",                    // 937
        "zucchini",                       // 938
        "spaghetti squash",               // 939
        "acorn squash",                   // 940
        "butternut squash",               // 941
        "cucumber",                       // 942
        "artichoke",                      // 943
        "bell pepper",                    // 944
        "cardoon",                        // 945
        "mushroom",                       // 946
        "Granny Smith apple",             // 947
        "strawberry",                     // 948
        "orange",                         // 949
        "lemon",                          // 950
        "fig",                            // 951
        "pineapple",                      // 952
        "banana",                         // 953
        "jackfruit",                      // 954
        "cherimoya",                      // 955
        "pomegranate",                    // 956
        "hay",                            // 957
        "carbonara",                      // 958
        "chocolate syrup",                // 959
        "dough",                          // 960
        "meatloaf",                       // 961
        "pizza",                          // 962
        "pot pie",                        // 963
        "burrito",                        // 964
        "red wine",                       // 965
        "espresso",                       // 966
        "tea cup",                        // 967
        "eggnog",                         // 968
        "mountain",                       // 969
        "bubble",                         // 970
        "cliff",                          // 971
        "coral reef",                     // 972
        "geyser",                         // 973
        "lakeshore",                      // 974
        "promontory",                     // 975
        "sandbar",                        // 976
        "beach",                          // 977
        "valley",                         // 978
        "volcano",                        // 979
        "baseball player",                // 980
        "bridegroom",                     // 981
        "scuba diver",                    // 982
        "rapeseed",                       // 983
        "daisy",                          // 984
        "yellow lady's slipper",          // 985
        "corn",                           // 986
        "acorn",                          // 987
        "rose hip",                       // 988
        "horse chestnut seed",            // 989
        "coral fungus",                   // 990
        "agaric",                         // 991
        "gyromitra",                      // 992
        "stinkhorn mushroom",             // 993
        "earth star fungus",              // 994
        "hen of the woods mushroom",      // 995
        "bolete mushroom",                // 996
        "ear of corn",                    // 997
        "toilet paper",                   // 998
        "ear",                            // 999
    ]
}
