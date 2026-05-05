clear; clc; close all;

%% =========================================================
% 1) CONSTANTS
% ==========================================================
rho_water = 1000;
g = 9.81;

%% =========================================================
% 2) PIPE / FLOW INPUTS
% ==========================================================
pipe_diameters = [0.040, 0.100];

Qmax_40  = 0.7 / 1000;
Qmax_100 = 6.0 / 1000;

flow_rates_40  = linspace(0.1 * Qmax_40,  Qmax_40, 8);
flow_rates_100 = linspace(0.1 * Qmax_100, Qmax_100, 8);

H_40  = 0.30;
H_100 = 0.50;

%% =========================================================
% 3) TURBINE STYLE DEFINITIONS
% name, eta_peak, lambda_opt, lambda_width, blockage_sensitivity
% ==========================================================
turbines = {
    'Axial in-pipe turbine',  0.35, 2.0, 0.9, 0.70
    'Helical screw turbine',  0.30, 1.2, 0.7, 0.55
    'Cross-flow turbine',    0.25, 1.6, 0.6, 0.85
    'Impulse micro turbine',  0.12, 3.0, 0.8, 1.10
};

%% =========================================================
% 4) GEOMETRY SWEEP
% ==========================================================
diameter_fractions = [0.35, 0.45, 0.55, 0.65, 0.75];
blade_counts = [3, 4, 5, 6, 8];
blade_angles_deg = [15, 25, 35, 45, 55];

results = [];
case_id = 0;

%% =========================================================
% 5) MAIN TURBINE SWEEP
% ==========================================================
for dp = 1:length(pipe_diameters)

    D_pipe = pipe_diameters(dp);
    A_pipe = pi * D_pipe^2 / 4;

    if abs(D_pipe - 0.040) < 1e-9
        flow_rates = flow_rates_40;
        H_available = H_40;
    else
        flow_rates = flow_rates_100;
        H_available = H_100;
    end

    for q = 1:length(flow_rates)

        Q = flow_rates(q);
        flow_Ls = Q * 1000;
        flow_Lmin = flow_Ls * 60;
        v_water = Q / A_pipe;

        P_hydraulic = rho_water * g * Q * H_available;

        for t = 1:size(turbines,1)

            turbine_name = turbines{t,1};
            eta_peak = turbines{t,2};
            lambda_opt = turbines{t,3};
            lambda_width = turbines{t,4};
            blockage_sensitivity = turbines{t,5};

            for df = 1:length(diameter_fractions)

                D_turbine = D_pipe * diameter_fractions(df);
                r_turbine = D_turbine / 2;
                blockage_ratio = (D_turbine / D_pipe)^2;

                for bc = 1:length(blade_counts)

                    blade_count = blade_counts(bc);

                    for ba = 1:length(blade_angles_deg)

                        blade_angle = blade_angles_deg(ba);

                        % Blade angle factor
                        angle_opt = 35;
                        angle_factor = exp(-((blade_angle - angle_opt) / 22)^2);

                        % Blade solidity factor
                        solidity_factor = 1 - exp(-blade_count / 4);

                        % Blockage penalty
                        blockage_penalty = max(1 - blockage_sensitivity * blockage_ratio, 0.05);

                        % Effective turbine efficiency
                        eta_turbine = eta_peak * angle_factor * solidity_factor * blockage_penalty;
                        eta_turbine = max(min(eta_turbine, eta_peak), 0);

                        % Optimum rotor speed from tip-speed ratio
                        omega_opt = lambda_opt * v_water / max(r_turbine, 1e-6);
                        rpm_opt = omega_opt * 60 / (2*pi);

                        % Turbine output power and torque
                        P_turbine = P_hydraulic * eta_turbine;

                        if omega_opt > 0
                            T_turbine = P_turbine / omega_opt;
                        else
                            T_turbine = 0;
                        end

                        % Basic feasibility
                        feasible = true;

                        if P_turbine <= 0
                            feasible = false;
                        end

                        if rpm_opt < 10
                            feasible = false;
                        end

                        if blockage_ratio > 0.75
                            feasible = false;
                        end

                        if feasible
                            case_id = case_id + 1;

                            results(case_id).pipe_diameter_m = D_pipe;
                            results(case_id).flow_m3s = Q;
                            results(case_id).flow_Ls = flow_Ls;
                            results(case_id).flow_Lmin = flow_Lmin;
                            results(case_id).head_m = H_available;
                            results(case_id).water_velocity_ms = v_water;
                            results(case_id).hydraulic_power_W = P_hydraulic;

                            results(case_id).turbine_type = string(turbine_name);
                            results(case_id).turbine_diameter_m = D_turbine;
                            results(case_id).diameter_fraction = diameter_fractions(df);
                            results(case_id).blade_count = blade_count;
                            results(case_id).blade_angle_deg = blade_angle;
                            results(case_id).blockage_ratio = blockage_ratio;

                            results(case_id).lambda_opt = lambda_opt;
                            results(case_id).eta_turbine = eta_turbine;
                            results(case_id).turbine_power_W = P_turbine;
                            results(case_id).turbine_torque_Nm = T_turbine;
                            results(case_id).rpm_opt = rpm_opt;
                            results(case_id).omega_opt = omega_opt;
                        end
                    end
                end
            end
        end
    end
end

if isempty(results)
    error('No feasible turbine designs found.');
end

T_turbine = struct2table(results);

%% =========================================================
% 6) SCORE AND SORT
% ==========================================================
P_norm = T_turbine.turbine_power_W / max(T_turbine.turbine_power_W);
eta_norm = T_turbine.eta_turbine / max(T_turbine.eta_turbine);

T_turbine.score = 0.65 * P_norm + 0.35 * eta_norm;
T_turbine = sortrows(T_turbine, 'score', 'descend');

%% =========================================================
% 7) EXTRACT TOP DESIGNS FOR EACH PIPE
% ==========================================================
Turbine40 = T_turbine(abs(T_turbine.pipe_diameter_m - 0.040) < 1e-9, :);
Turbine100 = T_turbine(abs(T_turbine.pipe_diameter_m - 0.100) < 1e-9, :);

Turbine40 = sortrows(Turbine40, 'score', 'descend');
Turbine100 = sortrows(Turbine100, 'score', 'descend');

topN = 10;

topTurbine_40 = Turbine40(1:min(topN,height(Turbine40)), :);
topTurbine_100 = Turbine100(1:min(topN,height(Turbine100)), :);

%% =========================================================
% 8) DISPLAY RESULTS
% ==========================================================
disp(' ');
disp('===============================================================');
disp('TOP TURBINE DESIGNS - 40 mm PIPE');
disp('===============================================================');
disp(topTurbine_40(:, {'turbine_type','flow_Ls','turbine_diameter_m', ...
    'blade_count','blade_angle_deg','blockage_ratio','rpm_opt', ...
    'turbine_power_W','eta_turbine','score'}));

disp(' ');
disp('===============================================================');
disp('TOP TURBINE DESIGNS - 100 mm PIPE');
disp('===============================================================');
disp(topTurbine_100(:, {'turbine_type','flow_Ls','turbine_diameter_m', ...
    'blade_count','blade_angle_deg','blockage_ratio','rpm_opt', ...
    'turbine_power_W','eta_turbine','score'}));

%% =========================================================
% 9) SAVE RESULTS
% ==========================================================
save('turbine_results.mat', 'T_turbine', 'topTurbine_40', 'topTurbine_100');

writetable(T_turbine, 'turbine_design_full.csv');
writetable(topTurbine_40, 'turbine_top10_40mm.csv');
writetable(topTurbine_100, 'turbine_top10_100mm.csv');

disp(' ');
disp('Saved files:');
disp('- turbine_results.mat');
disp('- turbine_design_full.csv');
disp('- turbine_top10_40mm.csv');
disp('- turbine_top10_100mm.csv');

%% =========================================================
% 10) PLOTS
% ==========================================================

figure;
scatter(T_turbine.rpm_opt, T_turbine.turbine_power_W, 25, ...
    T_turbine.pipe_diameter_m * 1000, 'filled');
xlabel('Optimum turbine speed (rpm)');
ylabel('Turbine output power (W)');
title('Turbine output power vs optimum rotor speed');
cb = colorbar;
cb.Label.String = 'Pipe diameter (mm)';
grid on;

figure;
scatter(T_turbine.blockage_ratio * 100, T_turbine.eta_turbine * 100, 25, ...
    T_turbine.turbine_power_W, 'filled');
xlabel('Blockage ratio (%)');
ylabel('Turbine efficiency (%)');
title('Effect of blockage ratio on turbine efficiency');
cb = colorbar;
cb.Label.String = 'Turbine power (W)';
grid on;

figure;
boxchart(categorical(T_turbine.turbine_type), T_turbine.turbine_power_W);
xlabel('Turbine type');
ylabel('Turbine output power (W)');
title('Turbine power comparison by turbine type');
grid on;

figure;
boxchart(categorical(T_turbine.turbine_type), T_turbine.eta_turbine * 100);
xlabel('Turbine type');
ylabel('Turbine efficiency (%)');
title('Turbine efficiency comparison by turbine type');
grid on;

figure;
scatter(T_turbine.flow_Ls, T_turbine.turbine_power_W, 30, ...
    categorical(T_turbine.turbine_type), 'filled');
xlabel('Flow rate (L/s)');
ylabel('Turbine output power (W)');
title('Turbine output power vs flow rate');
grid on;