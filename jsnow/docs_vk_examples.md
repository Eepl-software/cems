| example | status | FPS | missing features hit |
|---|---|---:|---|
| triangle | runs | 74.1104 | – |
| pipelines | runs | 4.8077 | dynamic state 2 |
| descriptorsets | runs | 22.5607 | – |
| dynamicuniformbuffer | runs | 18.1600 | – |
| pushconstants | runs | 23.2044 | – |
| specializationconstants | runs | 7.3457 | dynamic state 2 |
| texture | runs | 23.8670 | – |
| texturearray | runs | 30.2004 | – |
| texturecubemap | runs | 10.4942 | – |
| texturemipmapgen | runs | 7.1776 | separate images/samplers (bound per binding only) |
| gltfloading | runs | 9.1491 | – |
| gltfskinning | runs | 43.3333 | – |
| gltfscenerendering | runs, no frame presented | 0.9482 | – |
| instancing | runs, no frame presented | 0.3946 | – |
| indirectdraw | runs, no frame presented | 0.0741 | – |
| offscreen | runs, no frame presented | 0.6939 | – |
| shadowmapping | runs, no frame presented | 1.2006 | depth bias; dynamic state 3; vkCmdSetDepthBias |
| shadowmappingcascade | runs, no frame presented | 0.0928 | – |
| deferred | runs, no frame presented | 0.7474 | – |
| ssao | runs, no frame presented | 0.1630 | – |
| hdr | runs, no frame presented | 0.4296 | – |
| bloom | runs, no frame presented | 1.6717 | – |
| multisampling | runs | 13.4339 | – |
| particlesystem | runs | 9.7462 | primitive topology 0 |
| computeshader | fails (exit 255), no frame presented | – | compute pipelines; descriptor type 3 |
| stencilbuffer | runs | 17.4905 | stencil test |
| occlusionquery | runs | 11.0522 | – |
| radialblur | runs, no frame presented | 0.5112 | – |
| multithreading | runs, no frame presented | 0.6732 | – |
| pbrbasic | runs, no frame presented | 0.5448 | – |
| negativeviewportheight | runs | 21.0151 | – |
