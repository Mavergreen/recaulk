# RecaulkKernelFixes: notices

## KQueueScanContinuePatch (CC-0)

`kqueue_scan_restart.c` is ported from KQueueScanContinuePatch, by Wowfunhappy with assistance from krackers:
https://gist.github.com/Wowfunhappy/8212f5bea4c601ac9a6297789f232321. Wowfunhappy declared it CC-0 on
2026-11-23, in comment 6488041 on that gist.

## Lilu (BSD-3-Clause)

`kf_kernel_slide()` in `kqueue_scan_restart.c` is adapted, by way of that gist, from
https://github.com/acidanthera/Lilu/blob/137b4d9deb7022bb97fa9899303934534ff20ec7/Lilu/Sources/kern_mach.cpp,
under this licence:

    Copyright (c) 2016-2018, vit9696
    All rights reserved.
    
    Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
    
    1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    
    2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
    
    3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
    
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
