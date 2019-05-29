clear

% Initialization of physical model constants
thruster_config_2;
kn = Thruster_Config.kn;
kq = Thruster_Config.kq;
kv1 = Thruster_Config.kv1;
kv2 = Thruster_Config.kv2;
dv1 = Thruster_Config.dv1;
dv2 = Thruster_Config.dv2;
kv = Thruster_Config.kv;
kvv = Thruster_Config.kvv;
kt = Thruster_Config.kt;
kV = Thruster_Config.kV;
kVV = Thruster_Config.kVV;
kTV = Thruster_Config.kTV;
cTn = Thruster_Config.cTn;
cTnv = Thruster_Config.cTnv;
cQn = Thruster_Config.cQn;
cQnv = Thruster_Config.cQnv;

% Initialization of controller parameters
Kp = 5;
Ki = 10;
dt = .04; % Sampling frequency
rate = robotics.Rate(1/dt);
t = 0:dt:10;
Td = [(linspace(0,10,50)).';10*ones(((length(t)-1)/2)-100,1);(linspace(10,-10,100)).';-10*ones(((length(t)+1)/2)-100,1);(linspace(-10,0,50)).'];
% Td = [(linspace(0,10,50)).';(linspace(10,-10,100)).';(linspace(-10,0,50)).';zeros(51,1)];
% Td = 10*sin(1.88*t.');
nd = zeros(length(t),1);
nhat = zeros(length(t)+1,1);
vhat = nhat;
vahat = nhat;
u = zeros(length(t),1);
uprev = 0;
udotmax = 1/.01;
y = zeros(2,length(t));
c = 0;

% Covariances for KF:
Q = diag([2 .002 .002]);
R = diag([2.9497 .0047]);
P = zeros(3,3,length(t)+1);
P(:,:,1) = diag([2.9497 .0047 .0047]);

% Initialize Arduino Communication
fprintf(1, 'Entering Control Loop!\n');
s = serial('COM4', 'BaudRate', 9600);
fopen(s);
keyboard
reset(rate);
tic

% Enter loop
for i = 1:length(Td)
    
    % Control update
    nd(i) = (cTnv*vhat(i)+sign(Td(i))*sqrt((cTnv*vhat(i))^2+abs(4*cTn*Td(i))))/(2*cTn);
    ndot_d = (nd(i)-nhat(i))/dt;
    cdot = nhat(i) - nd(i);
    c = c + cdot*dt;
    a = ndot_d+kn*nd(i)+kq*(cQn*nd(i)*abs(nd(i))-cQnv*vhat(i)*abs(nd(i)));
    b = Kp*(nhat(i)-nd(i))+Ki*c;
    if a < b
        u(i) = ((a-b)/kv1)+dv1;
    elseif a > b
        u(i) = ((a-b)/kv2)+dv2;
    end
    if (abs(u(i)-uprev)/dt)>udotmax
        u(i) = uprev+sign(u(i)-uprev)*udotmax*dt;  
    end
    if abs(u(i)) > 5
        u(i) = 5*sign(u(i));
    end
    if u(i) <= dv1
        gamma = kv1*(u(i)-dv1);
    elseif u(i) >= dv2
        gamma = kv2*(u(i)-dv2);
    else
        gamma = 0;
    end
    uprev = u(i);
    
    % read tachometer and flow speed
    reading = fscanf(s, '%d,%d');
    reading = reading*5/1024;
    y_volts = reading(1);
    flow_volts = reading(2);
    y(1,i) = 49.9723*(2*y_volts-5);
    y(2,i) = (flow_volts-2.5)*.3/2.5;
    
    % Observer prediction
    T = cTn*nhat(i)*abs(nhat(i))-cTnv*vhat(i)*abs(nhat(i));
    Q = cQn*nhat(i)*abs(nhat(i))-cQnv*vhat(i)*abs(nhat(i));
    f = [-kn*nhat(i)-kq*Q+gamma;-kv*vhat(i)-kvv*(vhat(i)-vahat(i))*abs(vhat(i))+kt*T;-kV*vahat(i)-kVV*vahat(i)*abs(vahat(i))+kTV*T];
    H = [sign(nhat(i)) 0 0;0 0 1];
    K = P(:,:,i)*H.'/R;
    yhat = [abs(nhat(i));vahat(i)];
    xdot = f+K*(y(:,i)-yhat);
    nhat(i+1) = nhat(i)+xdot(1)*dt;
    vhat(i+1) = vhat(i)+xdot(2)*dt;
    vahat(i+1) = vahat(i)+xdot(3)*dt;
    A = [-kn-2*kq*cQn*abs(nhat(i))+kq*cQnv*vhat(i)*sign(nhat(i))                                                   kq*cQnv*abs(nhat(i))                       0
             2*kt*cTn*abs(nhat(i))-kt*cTnv*vhat(i)*sign(nhat(i)) -kv-2*kvv*abs(vhat(i))+kvv*vahat(i)*sign(vhat(i))-kt*cTnv*abs(nhat(i))        kvv*abs(vhat(i))
           2*kTV*cTn*abs(nhat(i))-kTV*cTnv*vhat(i)*sign(nhat(i))                                                 -kTV*cTnv*abs(nhat(i)) -kV-2*kVV*abs(vahat(i))];
    Pdot = A*P(:,:,i)+P(:,:,i)*A.'-K*H*P+Q;
    P(:,:,i+1) = P(:,:,i)+Pdot*dt;

    % u -> volts -> state_value (0-255) -> shift u into 0-10V range
    v_out = (-u(i) + 5.0);
    v_out = v_out * 255 / 10;
    fprintf(s, '%d\n', round(v_out));
    
    % Wait for next loop
    waitfor(rate);
end

toc
statistics(rate)
reading = fscanf(s, '%d,%d');
fprintf(s, '-99\n');
fclose(s);

% Plot results
figure
subplot(3,1,1)
plot(t,y(1,:),t,nhat(1:(end-1)),t,nd,'--k')
ylabel('Propeller Velocity [rad/s]')
legend({'y','$\hat{n}$','$n_{d}$'},'Interpreter','Latex')
grid
subplot(3,1,2)
plot(t,P(1,1,1:(end-1)),'g')
ylabel('Variance')
grid
subplot(3,1,3)
plot(t,u)
ylabel('Input [V]')
xlabel('Time [s]')
grid

figure
subplot(2,1,1)
hold on
ax = gca;
ax.ColorOrderIndex = 2;
plot(t,vhat(1:(end-1)),t,vhat(1:(end-1))+3*sqrt(P(2,2,1:(end-1))),'--k',t,vhat(1:(end-1))-3*sqrt(P(2,2,1:(end-1))),'--k')
ylabel('Axial Velocity [m/s]')
grid
hold off
subplot(2,1,2)
plot(t,y(2,:),t,vahat(1:(end-1)),t,vahat(1:(end-1))+3*sqrt(P(3,3,1:(end-1))),'--k',t,vahat(1:(end-1))-3*sqrt(P(3,3,1:(end-1))),'--k')
xlabel('Time [s]')
ylabel('Ambient Velocity [m/s]')
legend({'y','$\hat{v}$','$3\sigma bounds$'},'Interpreter','Latex')
grid