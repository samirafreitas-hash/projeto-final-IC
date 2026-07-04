import pandas as pd

# Arquivo CSV
csv_file = "nasa_dataset_battery.csv"

# Lê os dados
df = pd.read_csv(csv_file)

# Fator de escala (3 casas decimais)
SCALE = 1000

# Arquivo de saída
with open("battery_data.mem", "w") as f:

    for _, row in df.iterrows():

        values = []

        for value in row:
            # Converte float para inteiro
            fixed = int(round(value * SCALE))

            # Representação em complemento de dois (16 bits)
            fixed &= 0xFFFF

            values.append(f"{fixed:04X}")

        # Uma linha da memória
        f.write(" ".join(values) + "\n")

print("Arquivo battery_data.mem gerado com sucesso!")