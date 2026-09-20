class_name PopulationPool
extends RefCounted
## The two independent population caps a player has. Lives on its own class
## rather than inside the Population autoload because an autoload's name is a
## runtime singleton, not a type — only a class_name can be used in an export
## or a parameter's type annotation.
##
## MAIN is the ordinary Human population fed by Houses; PACT is the separate,
## smaller cap that an allied race's units spend (see Pacts), so allying adds
## army on top of your Humans rather than competing with them.

enum Kind { MAIN, PACT }
