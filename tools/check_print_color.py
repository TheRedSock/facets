"""Independent display invariants from the GPU's tabulated spectral inputs.
Oklab matrices: https://bottosson.github.io/posts/oklab/ (public domain).
No copy of the gamut-search algorithm: test hue/lightness/neutral behavior.
"""
import json
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]/"artifacts/print-acceptance"
def lab(rgb):
    lms=np.asarray(rgb)@np.array([[.4122214708,.5363325363,.0514459929],[.2119034982,.6806995451,.1073969566],[.0883024619,.2817188376,.6299787005]]).T
    return np.cbrt(lms)@np.array([[.2104542553,.7936177850,-.0040720468],[1.9779984951,-2.4285922050,.4505937099],[.0259040371,.7827717662,-.8086757660]]).T
def decode(v):return np.where(v<=.04045,v/12.92,((v+.055)/1.055)**2.4)
def angle(a,b):
    return np.abs(np.angle(np.exp(1j*(np.arctan2(a[:,2],a[:,1])-np.arctan2(b[:,2],b[:,1])))))*180/np.pi
r=json.loads((ROOT/"inputs.json").read_text())
xyz=np.array([p['xyz'] for p in r['inputs']]);rgb=xyz@np.array(r['xyz_to_rgb_columns'])
assert (rgb[:401]<0).any(),"Corpus must exercise negative RGB"
report={}
for view in [0,1]:
    image=np.array(Image.open(ROOT/f"view-{view}.png").convert('RGBA'))/255
    output=np.concatenate([image[0,:,:3],image[4,:,:3]])
    peak=np.max(rgb,axis=1)
    if view==1: toned=rgb/(1+np.maximum(peak,0))[:,None]
    else:
        mapped=peak*(1+peak/(1+3*.85)**2)/(1+peak)
        toned=rgb*(mapped/peak)[:,None]
    before=lab(toned);after=lab(decode(output))
    # Quantized colors with adequate chroma/lightness allow meaningful hue checks.
    mask=(np.linalg.norm(after[:,1:],axis=1)>.03)&(before[:,0]>.05)&(before[:,0]<.95)
    hue=angle(before[mask],after[mask]);dL=abs(before[mask,0]-after[mask,0])
    assert np.max(hue)<3.0,(view,"spectral hue",np.max(hue))
    assert np.max(dL)<.004,(view,"lightness",np.max(dL))
    clipped=lab(np.maximum(toned,0))
    clipped_hue=angle(before[mask],clipped[mask])
    assert np.max(clipped_hue)>8,"Fixture must detect the former preclipping hue error"
    neutral=output[401:];assert np.max(np.ptp(neutral,axis=1))<=1/255+1e-12
    assert np.min(np.diff(neutral.mean(axis=1)))>=0,"Neutral exposure ramp must be monotonic"
    assert np.max(np.abs(image[[1,5],:,3]-.25))<=.5/255+1e-12
    assert np.max(np.abs(image[[3,7],:,3]-.75))<=.5/255+1e-12
    report[str(view)]={"tested_hues":int(mask.sum()),"max_hue_degrees":float(hue.max()),"max_Oklab_L_error":float(dL.max()),"former_preclip_max_hue_degrees":float(clipped_hue.max())}
(ROOT/'color-report.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report));print('CHECK_COMPLETE: check_print_color')
