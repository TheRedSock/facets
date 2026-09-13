"""The acceptance metrics must reject stable blur, missing features and stale frames."""
import numpy as np
from check_appearance import signals,feature_metrics
mask=np.ones((16,16),bool)
ref=np.zeros((4,16,16,3));control=ref.copy()
for frame,x in enumerate([3,6,9,6]):ref[frame,3:13,x:x+1]=100
exact=signals(ref,ref,mask)
assert exact['spatial_rmse_lsb']==0 and exact['temporal_residual_lsb']==0 and exact['motion_gain']==1
stale=signals(ref,np.repeat(ref[:1],4,axis=0),mask)
assert stale['temporal_residual_lsb']>10 and stale['motion_gain']==0
blur=(np.roll(ref,1,axis=2)+ref+np.roll(ref,-1,axis=2))/3
blurred=feature_metrics(ref,blur,control,mask)
assert blurred['gain']<.85 and blurred['relative_residual']>.35
missing=feature_metrics(ref,control,control,mask)
assert missing['gain']==0 and missing['relative_residual']==1
biased=signals(ref,ref+3,mask);assert biased['mean_bias_lsb']==3
noisy=ref+np.random.default_rng(137).normal(0,.1,ref.shape)
f=feature_metrics(ref,noisy,control,mask)
assert .99<f['gain']<1.01 and f['correlation']>.99
print('CHECK_COMPLETE: test_appearance_metrics')
