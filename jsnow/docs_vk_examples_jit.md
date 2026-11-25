| example | status | FPS | missing features hit |
|---|---|---:|---|
| triangle | runs | 100.6271 | – |
| pipelines | runs | 19.5232 | dynamic state 2 |
| descriptorsets | runs | 22.3881 | – |
| dynamicuniformbuffer | runs | 24.8482 | – |
| pushconstants | runs | 32.9359 | – |
| specializationconstants | runs | 17.2047 | dynamic state 2 |
| texture | runs | 35.6329 | – |
| texturearray | runs | 40.4655 | – |
| texturecubemap | runs | 17.5177 | – |
| texturemipmapgen | runs | 14.0571 | separate images/samplers (bound per binding only) |
| gltfloading | runs | 15.1607 | – |
| gltfskinning | runs | 62.0946 | – |
| gltfscenerendering | runs, no frame presented | 1.9672 | – |
| instancing | runs, no frame presented | 0.9688 | – |
| indirectdraw | runs, no frame presented | 0.1356 | – |
| offscreen | runs, no frame presented | 1.2064 | – |
| shadowmapping | runs | 3.4751 | depth bias; dynamic state 3; vkCmdSetDepthBias |
| shadowmappingcascade | runs, no frame presented | 0.1265 | – |
| deferred | runs, no frame presented | 1.6391 | – |
| ssao | runs, no frame presented | 0.5165 | – |
| hdr | runs, no frame presented | 1.1129 | – |
| bloom | runs | 2.5427 | – |
| multisampling | runs | 20.5032 | resolve attachments (single-sampled: ignored) |
| particlesystem | runs | 13.2580 | primitive topology 0 |
| computeshader | runs | 7.1422 | – |
| stencilbuffer | runs | 17.6821 | stencil test |
| occlusionquery | runs | 14.4897 | – |
| radialblur | runs, no frame presented | 0.9646 | – |
| multithreading | runs, no frame presented | 1.5363 | – |
| pbrbasic | runs | 7.2029 | – |
| negativeviewportheight | runs | 23.9274 | – |
