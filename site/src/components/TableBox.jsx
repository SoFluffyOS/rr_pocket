// A table that scrolls sideways on a narrow screen instead of the page.
const TableBox = ({ head, rows }) => (
  <div className="my-4 overflow-x-auto">
    <table>
      <thead>
        <tr>
          {head.map((cell) => (
            <th key={cell}>{cell}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.map(([first, second], index) => (
          <tr key={index}>
            <td className="md:whitespace-nowrap">{first}</td>
            <td>{second}</td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
);

export default TableBox;
