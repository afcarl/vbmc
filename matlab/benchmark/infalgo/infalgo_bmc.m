function [history,post,algoptions] = infalgo_bmc(algo,algoset,probstruct)

algoptions.MaxFunEvals = probstruct.MaxFunEvals;

% Options from current problem
switch algoset
    case {0,'debug'}; algoset = 'debug'; algoptions.Debug = 1; algoptions.Plot = 'scatter';
    case {1,'base'}; algoset = 'base';           % Use defaults        
    otherwise
        error(['Unknown algorithm setting ''' algoset ''' for algorithm ''' algo '''.']);
end

PLB = probstruct.PLB;
PUB = probstruct.PUB;
LB = probstruct.LB;
UB = probstruct.UB;
x0 = probstruct.InitPoint;
D = size(x0,2);

diam = probstruct.PUB - probstruct.PLB;

kernelCov = diag(diam/10);     % Input length scales for GP likelihood model
lambda = 1;                     % Ouput length scale for GP likelihood model

% Do not add log prior to function evaluation, already passed to BMC 
probstruct.AddLogPrior = false;

algo_timer = tic;

% Initialize Bayesian Monte Carlo with samples from prior
SaveTicks = probstruct.SaveTicks(probstruct.SaveTicks <= algoptions.MaxFunEvals);

Nmax = max(SaveTicks);
Niter = numel(SaveTicks);

priorMean = probstruct.PriorMean;
priorVar = probstruct.PriorVar;

% Generate random samples from prior
X = [x0(1,:); ...
        bsxfun(@plus, ...
        bsxfun(@times,randn(Nmax-1,D),sqrt(priorVar)),...
        priorMean)];

% Compute log likelihoods at points
y = zeros(Nmax,1);
for i = 1:Nmax
    y(i) = infbench_func(X(i,:),probstruct);
end

mu = zeros(1,Niter);
ln_var = zeros(1,Niter);
for i = 1:Niter
    X_train = X(1:SaveTicks(i),:);
    [mu(i), ln_var(i), kernelCov, lambda] = bq([], ...
        priorMean, diag(priorVar), kernelCov, lambda, [], ...
        X_train, y(1:SaveTicks(i)));
end
TotalTime = toc(algo_timer);

vvar = max(real(exp(ln_var)),0);

history = infbench_func(); % Retrieve history
% history.scratch.output = output;
history.TotalTime = TotalTime;
history.Output.X = X;
history.Output.y = y;
if ~probstruct.AddLogPrior      % y stores log posteriors, so add prior now
    lnp = infbench_lnprior(history.Output.X,probstruct);
    history.Output.y = history.Output.y + lnp;
end

% Store computation results
post.lnZ = mu(end);
post.lnZ_var = vvar(end);
X_train = history.Output.X;
y_train = history.Output.y;
[post.gsKL,post.Mean,post.Cov,post.Mode] = computeStats(X_train,y_train,probstruct);

% Return estimate, SD of the estimate, and gauss-sKL with true moments
N = history.SaveTicks(1:Niter);
history.Output.N = N;
history.Output.lnZs = mu;
history.Output.lnZs_var = vvar;
for iIter = 1:Niter
    X_train = history.Output.X(1:N(iIter),:);
    y_train = history.Output.y(1:N(iIter));
    [gsKL,~,~,Mode] = computeStats(X_train,y_train,probstruct);
    history.Output.gsKL(iIter) = gsKL;
    history.Output.Mode(iIter,:) = Mode;
end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [gsKL,Mean,Cov,Mode] = computeStats(X,y,probstruct)
%COMPUTE_STATS Compute additional statistics.
    
% Compute Gaussianized symmetric KL-divergence with ground truth
gp.X = X;
gp.y = y;
gp.meanfun = 4; % Negative quadratic mean fcn

Ns_moments = 2e4;
xx = gplite_sample(gp,Ns_moments);
Mean = mean(xx,1);
Cov = cov(xx);
[kl1,kl2] = mvnkl(Mean,Cov,probstruct.Mean,probstruct.Cov);
gsKL = 0.5*(kl1 + kl2);

Mode = gplite_fmin(gp,[],1);    % Max flag - finds maximum

end