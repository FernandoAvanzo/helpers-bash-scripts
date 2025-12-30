import React, { useState } from 'react';
import saveAs from 'file-saver';
import html2canvas from 'html2canvas';
import { Line } from 'react-chartjs-2';
import {
  Chart as ChartJS,
  LineElement,
  LinearScale,
  CategoryScale,
  PointElement,
  Title,
  Tooltip,
  Legend,
  Filler
} from 'chart.js';
import {Input} from "postcss";

ChartJS.register(
    LineElement,
    LinearScale,
    CategoryScale,
    PointElement,
    Title,
    Tooltip,
    Legend,
    Filler
);

const presets = {
  'Wet Track': { angle: 20, car: 'Mercedes W14', speedKmh: 180 },
  'Qualifying': { angle: 30, car: 'Red Bull RB19', speedKmh: 300 },
  'Low Downforce': { angle: 5, car: 'Ferrari SF-23', speedKmh: 320 }
};

function Button({children, variant = "default", onClick}) {
  const variants = {
    default: "bg-blue-500 text-white hover:bg-blue-600",
    outline: "border border-blue-500 text-blue-500 hover:bg-blue-500 hover:text-white",
    ghost: "text-blue-500 hover:bg-blue-100"
  };

  const className = `px-4 py-2 rounded ${variants[variant] || variants.default}`;

  return (
      <button className={className} onClick={onClick}>
        {children}
      </button>
  );
}

function Slider({min, max, step, value, onValueChange}) {
  return (
      <input
          type="range"
          min={min}
          max={max}
          step={step}
          value={value}
          onChange={(e) => onValueChange([Number(e.target.value)])}
          className="w-full"
      />
  );
}

function Select({value, onValueChange, children}) {
  return (
      <select
          value={value}
          onChange={(e) => onValueChange(e.target.value)}
          className="p-2 border rounded"
      >
        {children}
      </select>
  );
}

function SelectTrigger({children, ...props}) {
  return (
      <div className="select-trigger" {...props}>
        {children}
      </div>
  );
}

function SelectContent({children}) {
  return (
      <div className="absolute mt-1 bg-white border border-gray-300 rounded shadow-md z-10">
        {children}
      </div>
  );
}

function SelectItem({children, value}) {
  return (
      <option value={value}>
        {children}
      </option>
  );
}

function SelectValue({placeholder}) {
  return <span>{placeholder}</span>;
}

function Textarea(props) {
  return (
      <textarea
          {...props}
          className={`p-2 border rounded ${props.className || ''}`}
      />
  );
}

function Card({children}) {
  return (
      <div className="bg-white shadow rounded p-4">
        {children}
      </div>
  );
}

function CardContent(props) {
  return (
      <div className="card-content">
        {props.children}
      </div>
  );
}

export default function App() {
  const [jsonInput, setJsonInput] = useState('');
  const [setupName, setSetupName] = useState('');
  const [savedConfigs, setSavedConfigs] = useState([
    { name: 'Balanced Setup', config: { speedKmh: 220, angle: 18, car: 'Ferrari SF-23' } },
    { name: 'Straight Line Max', config: { speedKmh: 320, angle: 5, car: 'Mercedes W14' } },
    { name: 'Rain Race', config: { speedKmh: 160, angle: 25, car: 'Red Bull RB19' } }
  ]);

  const [speedKmh, setSpeedKmh] = useState(250);
  const [angle, setAngle] = useState(15);
  const [car, setCar] = useState('Ferrari SF-23');

  const rho = 1.225;
  const A = 1.5;
  const speed = speedKmh / 3.6;
  const angleFactor = 1 + angle / 45;
  const Cd = { 'Mercedes W14': 0.82, 'Red Bull RB19': 0.75, 'Ferrari SF-23': 0.8 }[car];

  const simData = Array.from({ length: 51 }, (_, i) => 100 + i * 4);
  const dfSeries = simData.map(v => 0.5 * rho * A * (v / 3.6) ** 2 * angleFactor);
  const drSeries = simData.map(v => 0.5 * rho * A * Cd * (v / 3.6) ** 2);

  const chartData = {
    labels: simData,
    datasets: [
      {
        label: 'Downforce (N)',
        data: dfSeries,
        borderColor: 'green',
        backgroundColor: 'rgba(0, 128, 0, 0.2)',
        fill: true
      },
      {
        label: 'Drag (N)',
        data: drSeries,
        borderColor: 'red',
        backgroundColor: 'rgba(255, 0, 0, 0.2)',
        fill: true
      }
    ]
  };

  const chartOptions = {
    responsive: true,
    plugins: {
      legend: { position: 'top' },
      title: {
        display: true,
        text: 'Aerodynamic Forces vs Speed'
      }
    },
    scales: {
      x: {
        type: 'category',
        title: { display: true, text: 'Speed (km/h)' }
      },
      y: {
        title: { display: true, text: 'Force (N)' }
      }
    }
  };

  const exportCSV = () => {
    const csvHeader = 'Speed (km/h),Downforce (N),Drag (N)\n';
    const csvRows = simData.map((v, i) => `${v},${dfSeries[i].toFixed(2)},${drSeries[i].toFixed(2)}`).join('\n');
    const blob = new Blob([csvHeader + csvRows], { type: 'text/csv;charset=utf-8;' });
    saveAs(blob, `f1_aero_sim_${car.replace(/\s/g, '_')}.csv`);
  };

  const exportPNG = () => {
    const chartArea = document.querySelector('#chart-area');
    if (!chartArea) return;
    html2canvas(chartArea).then(canvas => {
      canvas.toBlob(blob => {
        if (blob) saveAs(blob, `f1_aero_chart_${car.replace(/\s/g, '_')}.png`);
      });
    });
  };

  const importJSON = (json) => {
    try {
      const config = typeof json === 'string' ? JSON.parse(json) : json;
      if (config.speedKmh) setSpeedKmh(config.speedKmh);
      if (config.angle) setAngle(config.angle);
      if (config.car) setCar(config.car);
    } catch (err) {
      console.error('Invalid setup JSON:', err);
    }
  };

  const saveCurrentSetup = () => {
    if (!setupName.trim()) return;
    const newConfig = { name: setupName, config: { speedKmh, angle, car } };
    setSavedConfigs(prev => [...prev, newConfig]);
    setSetupName('');
  };

  return (
      <div className="p-4 max-w-4xl mx-auto">
        <h1 className="text-2xl font-bold mb-4 text-center">F1 Downforce Simulator</h1>

        <div className="mb-4 flex gap-2 flex-wrap">
          {Object.entries(presets).map(([label, config]) => (
              <Button key={label} variant="outline" onClick={() => importJSON(config)}>{label}</Button>
          ))}
          <Button onClick={exportCSV}>Export CSV</Button>
          <Button onClick={exportPNG}>Export PNG</Button>
        </div>

        <div className="mb-6">
          <div className="mb-4">
            <label className="block font-medium mb-1">Wing Angle: {angle}°</label>
            <Slider min={0} max={45} step={1} value={[angle]} onValueChange={([val]) => setAngle(val)} />
          </div>
          <div className="mb-4">
            <label className="block font-medium mb-1">Car Profile</label>
            <Select value={car} onValueChange={setCar}>
              <SelectTrigger><SelectValue placeholder="Select Car" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="Ferrari SF-23">Ferrari SF-23</SelectItem>
                <SelectItem value="Mercedes W14">Mercedes W14</SelectItem>
                <SelectItem value="Red Bull RB19">Red Bull RB19</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="mb-4">
            <label className="block font-medium mb-1">Speed (km/h): {speedKmh}</label>
            <Slider min={100} max={350} step={5} value={[speedKmh]} onValueChange={([val]) => setSpeedKmh(val)} />
          </div>
          <div className="mb-4">
            <label className="block font-medium mb-1">3D Wing Angle Preview</label>
            <div style={{ perspective: '800px', height: '150px' }}>
              <div
                  style={{
                    transform: `rotateX(${angle}deg)`,
                    width: '120px',
                    height: '40px',
                    margin: '0 auto',
                    background: '#888',
                    borderRadius: '6px',
                    transformStyle: 'preserve-3d',
                    boxShadow: '0 10px 20px rgba(0,0,0,0.3)',
                    transition: 'transform 0.3s ease-in-out'
                  }}
              />
            </div>
          </div>
        </div>

        <div className="mb-4">
          <label className="block font-medium mb-1">Import Custom Setup (JSON)</label>
          <Textarea
              className="w-full h-32 mb-2"
              placeholder='{"speedKmh": 250, "angle": 15, "car": "Ferrari SF-23"}'
              value={jsonInput}
              onChange={(e) => setJsonInput(e.target.value)}
          />
          <Button onClick={() => importJSON(jsonInput)}>Apply Setup</Button>
        </div>

        <div className="mb-4">
          <label className="block font-medium mb-1">Save Current Setup</label>
          <div className="flex gap-2 items-center mb-2">
            <Input
                placeholder="Setup name"
                value={setupName}
                onChange={(e) => setSetupName(e.target.value)}
            />
            <Button onClick={saveCurrentSetup}>Save Setup</Button>
          </div>
        </div>

        <div className="mb-4">
          <label className="block font-medium mb-1">Saved Configurations</label>
          <div className="grid gap-2">
            {savedConfigs.map(({ name, config }) => (
                <Button key={name} variant="ghost" onClick={() => importJSON(config)}>{name}</Button>
            ))}
          </div>
        </div>

        <Card>
          <CardContent id="chart-area">
            <h2 className="text-lg font-semibold mb-2">Downforce vs Drag Chart</h2>
            <Line data={chartData} options={chartOptions} />
          </CardContent>
        </Card>
      </div>
  );
}
