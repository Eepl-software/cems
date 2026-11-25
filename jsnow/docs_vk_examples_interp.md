| example | status | FPS | missing features hit |
|---|---|---:|---|
| triangle | runs | 86.1397 | – |
| pipelines | runs | 6.3586 | dynamic state 2 |
| descriptorsets | runs | 21.3075 | – |
| dynamicuniformbuffer | runs | 8.2087 | – |
| pushconstants | runs | 27.0235 | – |
| specializationconstants | runs | 9.0213 | dynamic state 2 |
| texture | runs | 28.8053 | – |
| texturearray | runs | 39.5983 | – |
| texturecubemap | runs | 15.2588 | – |
| texturemipmapgen | runs | 9.8883 | separate images/samplers (bound per binding only) |
| gltfloading | runs | 11.5484 | – |
| gltfskinning | runs | 50.8591 | – |
| gltfscenerendering | runs, no frame presented | 1.1803 | – |
| instancing | runs, no frame presented | 0.4851 | – |
| indirectdraw | runs, no frame presented | 0.0858 | – |
| offscreen | runs, no frame presented | 0.8894 | – |
| shadowmapping | runs, no frame presented | 1.8516 | depth bias; dynamic state 3; vkCmdSetDepthBias |
| shadowmappingcascade | runs, no frame presented | 0.1110 | – |
| deferred | runs, no frame presented | 0.9597 | – |
| ssao | runs, no frame presented | 0.1998 | – |
| hdr | runs, no frame presented | 0.5532 | – |
| bloom | runs, no frame presented | 1.8361 | – |
| multisampling | runs | 15.0320 | resolve attachments (single-sampled: ignored) |
| particlesystem | runs | 10.9462 | primitive topology 0 |
| computeshader | runs | 2.7082 | – |
| stencilbuffer | runs | 22.2858 | stencil test |
| occlusionquery | runs | 13.9070 | – |
| radialblur | runs, no frame presented | 0.7321 | – |
| multithreading | runs, no frame presented | 1.1030 | – |
| pbrbasic | runs, no frame presented | 0.6246 | – |
| negativeviewportheight | runs | 16.5850 | – |
