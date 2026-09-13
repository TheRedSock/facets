"""The acceptance metrics must reject stable blur, missing features and stale frames."""
import numpy as np
import copy
from check_appearance import signals,feature_metrics,threshold_errors,REQUIRED_LIMITS,source_errors,config_errors
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
config={'schema':2,'cases':['test'],'profiles':{'draft':{'rung':'clip_bake'},'reference':{'rung':'reference'}},'case_profiles':{'test':['draft','reference']},'references':{'test':'reference'}}
assert not config_errors(config)
for key,value in [('schema',1),('case_profiles',{}),('references',{}),('references',{'test':'draft'}),('case_profiles',{'test':['draft','draft','reference']})]:
    invalid=copy.deepcopy(config);invalid[key]=value
    assert config_errors(invalid),(key,value)
valid={'schema':1,'config_sha256':'hash','reviewer':'test fixture','review_notes':{'test':'Explicit synthetic reference'},'selected_profiles':{'test':'draft'},'limits':{'test':{key:1 for key in REQUIRED_LIMITS}}}
assert not threshold_errors(config,valid,'hash')
assert threshold_errors(config,{},'hash')
for key,value in [('selected_profiles',{}),('selected_profiles',[]),('selected_profiles',{'test':'reference'}),('limits',{'test':{}}),('limits',[]),('review_notes',{}),('config_sha256','stale')]:
    invalid=copy.deepcopy(valid);invalid[key]=value
    assert threshold_errors(config,invalid,'hash'),(key,value)
for value in [float('nan'),float('inf'),-1,True,'1']:
    invalid=copy.deepcopy(valid);invalid['limits']['test']['spatial_rmse_lsb']=value
    assert threshold_errors(config,invalid,'hash')
assert source_errors({}) and source_errors({'../outside-repo':'fake'})
print('CHECK_COMPLETE: test_appearance_metrics')
