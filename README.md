a weird replacement for smartsnap -- not in a condition to be put on the workshop yet

wraps grids and guidelines around faces of **physical mesh convexes** as opposed to bounding boxes

## gallery
<img width="957" height="593" alt="image" src="https://github.com/user-attachments/assets/129b73b2-6f9b-4052-a366-c234c53e42ec" />

<img alt="abababa" src="https://i.postimg.cc/0QT10wqs/asdf.gif"/>

demo vid (click to go to yt)
[![asdfdsffff](https://img.youtube.com/vi/b3End2VHfE8/maxresdefault.jpg)](https://www.youtube.com/watch?v=b3End2VHfE8)

why cant i embed gifs wtf


## todo
- real config panel
- make the shapedata function run on a slown down coroutine cuz it fat
- implement "polar patterns"
  - these partially exist in the code already it just changes the denominations of angles that the polar grid splits to when the area of a cell becomes too large at further radii,, cuz some ppl are freaks for 30 deg angles rather than 90/(2^n)
- OBB fallback
- accommodate npcs
- compat w physparent
- compat w dsit
- accommodate known builder props by adjusting the grid to fit their bill the best when selected
  - hunter
  - squad
  - sprops
- accomodate the world
  - should it use world brush data like what jazztronauts does?
  - should it just be a grid from hitpos/norm? not consistent for any surface thats not cardinal
- make controls like alt and scroll rebindable


## known issues
- some parametric rays arent built/drawn when they should be, esp on thinner polys
- some weird and unique models dont work w/ this at all for their own reasons
- shapedata function is super slow for very high poly/multiconvexed physobjs its gotta be split into a moderated coroutine
- frames arent that great but also arent that much worse than smartsnap per line so,,,
